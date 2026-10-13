require_relative "owner_connection"

# 入口の行列の 2 回目と、操作者のいない入口の公開 API の単体のために、テナントの表ごとに、設定 app.matrix_cross_read が
# on のときだけ全行を読ませる SELECT のポリシーと、全行を UPDATE の対象に入れる UPDATE のポリシーを足し外す
# （docs/guides/testing.md「行列テストとの分担」）。RLS が他社の行を隠すと、公開 API の scope や所有の条件を外しても
# 結果が変わらないので、RLS を開いた結果と比べて抜けを捕まえる。UPDATE と SELECT ... FOR UPDATE は、SELECT のポリシーに加えて
# UPDATE のポリシーの USING を満たす行しか対象にしないので、SELECT だけを開いても所有の条件の抜けが見えない。
# UPDATE のポリシーは書いた後の行を何も通さない（WITH CHECK (false)）ので、他社の行を引いた書き込みは owner_write の
# WITH CHECK に当たって例外になる。ただし設定が on の間は、他社の行を自社の名義に書き換える UPDATE が通るので、
# 単体は他社の行が変わらないことも確かめる。
# アプリのロールは app.* の設定を自由に変えられるので、このポリシーが本番に載れば、全テナントの行を読み、他社の行を自社の名義に書き換える抜け道になる。
# そのため SQL はここにだけ置き、lib/tenant_table.rb とマイグレーションには置かない。
# structure.sql に混ざれば bin/check-structure が、消し忘れれば spec/db/tenant_enforcement_spec.rb が落とす
module MatrixCrossRead
  POLICY = "matrix_cross_read".freeze
  UPDATE_POLICY = "matrix_cross_update".freeze
  SETTING = "app.matrix_cross_read".freeze

  # 所有ロールの接続で、全表の 2 つのポリシーを 1 つのトランザクションで足す。途中で失敗すると全部が巻き戻り、足した分は残らない。
  # 世界を開く前に呼ぶ。ポリシーの足し外しは表のロックを取るので、全表に書いた世界の外側のトランザクションが開いている間は、
  # それが閉じるまで待ち、世界と同じスレッドから呼ぶと終わらない。
  # 同じ名前のポリシーがあれば、別の実行が同じテストの DB で行列を流しているか、途中で止めた実行が残したので、外さずに失敗する
  def self.add!
    with_owner_connection do |connection|
      connection.transaction do
        MatrixWorld.tenant_tables.each do |table|
          # WITH CHECK を書き落とすと PostgreSQL は USING を WITH CHECK に使い、設定が on の間は他社の名義の行を書ける。
          # 許可のポリシーの WITH CHECK は OR でつながるので、false なら書いた後の行は owner_write の WITH CHECK だけで判定される
          connection.execute(<<~SQL)
            CREATE POLICY #{POLICY} ON #{connection.quote_table_name(table)} FOR SELECT
              USING (current_setting('#{SETTING}', true) = 'on');
            CREATE POLICY #{UPDATE_POLICY} ON #{connection.quote_table_name(table)} FOR UPDATE
              USING (current_setting('#{SETTING}', true) = 'on') WITH CHECK (false);
          SQL
        end
      end
    end
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::DuplicateObject)

    raise "#{POLICY} か #{UPDATE_POLICY} のポリシーがすでにある。同じテストの DB で行列を流しているほかの実行が無ければ、" \
      "途中で止めた実行が残したものなので、MatrixCrossRead.remove! で外す（docs/guides/testing.md「行列テストとの分担」）"
  end

  # グループの前にポリシーを足し、後に外す。外すのは、このグループが足し終えたときだけにする。
  # rspec は before(:context) が失敗しても after(:context) を走らせ（rspec-core 3.13 の lib/rspec/core/example_group.rb の
  # ExampleGroup.run が ensure で run_after_context_hooks を呼ぶ）、足すのに失敗したときに外すと、同じ DB に先に足した
  # 別の実行のポリシーを消すからである。after(:context) は登録の逆の順に走るので、ほかのフックより先に呼べば、
  # ほかのフックが開いた世界を閉じた後に外れる
  def self.share(group)
    group.before(:context) do
      MatrixCrossRead.add!
      @matrix_cross_read_added = true
    end
    group.after(:context) { MatrixCrossRead.remove! if @matrix_cross_read_added }
  end

  # ブロックの間だけポリシーを足す。足すのに失敗したときは外さない（share と同じ理由）
  def self.with_policies
    add!
    begin
      yield
    ensure
      remove!
    end
  end

  # 足していない表があっても失敗しない。spec と補助は直に呼ばず、share か with_policies を通す。
  # 途中で止めた実行が残したポリシーを手で外すときにだけ、直に呼ぶ
  def self.remove!
    with_owner_connection do |connection|
      connection.transaction do
        MatrixWorld.tenant_tables.product([ POLICY, UPDATE_POLICY ]).each do |table, policy|
          connection.execute("DROP POLICY IF EXISTS #{policy} ON #{connection.quote_table_name(table)}")
        end
      end
    end
  end

  # example のトランザクションの中だけで RLS の SELECT と UPDATE を開く。example のセーブポイントを巻き戻すと設定も戻る。
  # ロールや DB の既定に書くと、example の外とほかの spec の接続にも開く
  def self.on!
    ActiveRecord::Base.lease_connection.select_value("SELECT set_config('#{SETTING}', 'on', true)")
  end

  # 接続先の名前がテストの DB でなければ、何もせずに失敗する。開発の DB に足すと、そこでアプリのロールが全行を読める
  def self.with_owner_connection
    OwnerConnection.connection_pool.with_connection do |connection|
      database = connection.current_database
      unless Rails.env.test? && database.match?(/_test(_|\z)/)
        raise "テストの DB ではない #{database}（#{Rails.env}）に、全行を読ませるポリシーを足そうとした"
      end

      yield connection
    end
  end
  private_class_method :with_owner_connection
end
