require "rails_helper"
require_relative "../support/owner_connection"
require_relative "../support/tenant_helpers"

# lib/tenant_table.rb の補助が作る表を、実際に作って確かめる。
# 表は所有ロールで作って消し、行の読み書きはアプリのロールで RLS を通して行う。
RSpec.describe TenantTable do
  include TenantHelpers

  # 所有ロールの接続で作った表は、コミットしないとアプリのロールの接続から見えない。
  # そのため例ごとのトランザクションを使わず、作った表と行は例の後で消す
  self.use_transactional_tests = false

  let(:migration) do
    Class.new(ActiveRecord::Migration[8.1]) do
      include TenantTable

      def change
        create_tenant_table :tenant_table_spec_parents, comment: "[基盤] 試験用の親" do |t|
          t.boolean :published, null: false, default: false
        end
        create_tenant_table :tenant_table_spec_children, comment: "[基盤] 試験用の子"
        add_tenant_reference :tenant_table_spec_children, :tenant_table_spec_parents
        add_partner_read_policy :tenant_table_spec_parents, using: "published"
      end
    end
  end

  def migrate(direction)
    instance = migration.new
    run = -> { instance.exec_migration(OwnerConnection.lease_connection, direction) }
    ActiveRecord::Migration.suppress_messages do
      # bin/rails db:rollback では strong_migrations は down を検査しない。exec_migration は向きを伝えないので、ここで合わせる
      OwnerConnection.transaction { direction == :down ? instance.safety_assured(&run) : run.call }
    end
  end

  def migrated?
    OwnerConnection.lease_connection.table_exists?(:tenant_table_spec_parents)
  end

  def policies
    OwnerConnection.lease_connection.select_rows(<<~SQL)
      SELECT tablename, policyname, cmd FROM pg_policies
      WHERE tablename LIKE 'tenant_table_spec_%' ORDER BY 1, 2
    SQL
  end

  after do
    migrate(:down) if migrated?
    # アプリのロールは tenants を消せないので、所有ロールで消す
    OwnerConnection.lease_connection.execute("DELETE FROM tenants WHERE code LIKE 'tenant_table_spec_%'")
  end

  it "作った表に RLS とポリシーが付き、巻き戻すと表ごと消える" do
    migrate(:up)
    expect(policies).to eq([
      [ "tenant_table_spec_children", "owner_write", "ALL" ],
      [ "tenant_table_spec_parents", "owner_write", "ALL" ],
      [ "tenant_table_spec_parents", "partner_read", "SELECT" ]
    ])

    migrate(:down)
    expect(policies).to be_empty
    expect(migrated?).to be(false)
  end

  it "表に説明が付く" do
    migrate(:up)
    expect(OwnerConnection.lease_connection.table_comment(:tenant_table_spec_parents)).to eq("[基盤] 試験用の親")
  end

  context "作った表に、アプリのロールで書く" do
    before do
      migrate(:up)
      app_role = ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:username)
      OwnerConnection.lease_connection.execute(<<~SQL)
        GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_table_spec_parents, tenant_table_spec_children
        TO #{OwnerConnection.lease_connection.quote_column_name(app_role)}
      SQL
    end

    let!(:tenant_a) { create_tenant("tenant_table_spec_a") }
    let!(:tenant_b) { create_tenant("tenant_table_spec_b") }

    def insert_parent(tenant, published: false)
      Tenancy.with_tenant(tenant) do
        connection.select_value(<<~SQL)
          INSERT INTO tenant_table_spec_parents (owner_tenant_id, published)
          VALUES (#{connection.quote(tenant)}, #{published}) RETURNING id
        SQL
      end
    end

    def insert_child(tenant, parent_id)
      Tenancy.with_tenant(tenant) do
        connection.select_value(<<~SQL)
          INSERT INTO tenant_table_spec_children (owner_tenant_id, tenant_table_spec_parent_id)
          VALUES (#{connection.quote(tenant)}, #{connection.quote(parent_id)}) RETURNING id
        SQL
      end
    end

    it "子は同じテナントの親を指せ、相手テナントの親を指すと複合外部キーに拒否される" do
      parent_a = insert_parent(tenant_a)
      parent_b = insert_parent(tenant_b, published: true)

      expect(insert_child(tenant_a, parent_a)).to be_present
      expect { insert_child(tenant_a, parent_b) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "partner_read は SELECT だけを広げ、相手の行への書き込みは 0 行のまま" do
      parent_a = insert_parent(tenant_a)
      published_b = insert_parent(tenant_b, published: true)
      insert_parent(tenant_b, published: false)

      Tenancy.with_tenant(tenant_a) do
        expect(connection.select_values("SELECT id FROM tenant_table_spec_parents")).to contain_exactly(parent_a, published_b)
        expect(connection.update("UPDATE tenant_table_spec_parents SET published = false WHERE id = #{connection.quote(published_b)}")).to eq(0)
        expect(connection.delete("DELETE FROM tenant_table_spec_parents WHERE id = #{connection.quote(published_b)}")).to eq(0)
      end
    end
  end
end
