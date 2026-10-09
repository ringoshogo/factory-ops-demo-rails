# テナントの表を作るマイグレーションの補助（docs/architecture/data-model.md「テナントの持ち方」「RLS」）。
# テナントの表は必ず create_tenant_table で作る。付け忘れは spec/db/tenant_enforcement_spec.rb が落とす。
# 表の説明（COMMENT ON TABLE）は comment: で渡す。書式は data-model.md「全テーブルに共通の規則」、欠けは spec/db/table_comments_spec.rb が落とす。
# どれも change の中で使え、巻き戻すと逆の操作になる。
module TenantTable
  # owner_tenant_id・UUIDv7 の主キー・UNIQUE (owner_tenant_id, id) を持つ表を作り、
  # FORCE ROW LEVEL SECURITY と owner_write のポリシーを付ける。comment: は表の説明で、表に付ける。
  def create_tenant_table(table, comment: nil, **options)
    create_table table, id: :uuid, default: -> { "uuidv7()" }, comment:, **options do |t|
      t.uuid :owner_tenant_id, null: false
      t.foreign_key :tenants, column: :owner_tenant_id
      # 子の複合外部キーの参照先
      t.index [ :owner_tenant_id, :id ], unique: true
      yield t if block_given?
    end

    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<~SQL
            ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
            ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
            CREATE POLICY owner_write ON #{table} FOR ALL
              USING (owner_tenant_id = current_tenant_id())
              WITH CHECK (owner_tenant_id = current_tenant_id());
          SQL
        end
      end
      # 表を落とせばポリシーも消えるので、down は drop_table に任せる
    end
  end

  # 同じコンテキストの親を参照する列を足し、(owner_tenant_id, 列) から親の (owner_tenant_id, id) へ
  # 複合外部キーを張る。親と所有テナントが食い違う行は DB が拒否する。
  # 同じマイグレーションで作った子の表に使う。strong_migrations は検証付きの外部キーを常に止めるが、
  # 新しい表には検証する行が無いので許す。
  def add_tenant_reference(table, parent, column: "#{parent.to_s.singularize}_id")
    add_column table, column, :uuid, null: false
    add_index table, [ :owner_tenant_id, column ]
    safety_assured do
      add_foreign_key table, parent, column: [ :owner_tenant_id, column ], primary_key: [ :owner_tenant_id, :id ]
    end
  end

  # 相手テナントが読む経路の、読み取り専用のポリシーを足す。書き込みは owner_write のまま変わらない。
  def add_partner_read_policy(table, using:)
    reversible do |dir|
      dir.up do
        safety_assured { execute "CREATE POLICY partner_read ON #{table} FOR SELECT USING (#{using})" }
      end
      dir.down do
        safety_assured { execute "DROP POLICY partner_read ON #{table}" }
      end
    end
  end
end
