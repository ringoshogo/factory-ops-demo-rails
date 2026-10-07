require "rails_helper"

# テナントの表に RLS が欠けていないことを、テスト DB のカタログで確かめる（adr/001 決定 5）。
# スキーマはマイグレーションから structure.sql を経て読み込まれるので、ここが通れば本番と同じ防壁がある。
RSpec.describe "テナントの強制" do
  let(:connection) { ActiveRecord::Base.lease_connection }

  let(:tenant_tables) do
    connection.select_values(<<~SQL)
      SELECT table_name FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'owner_tenant_id'
      ORDER BY table_name
    SQL
  end

  it "テナントの表がある" do
    expect(tenant_tables).to include("users")
  end

  describe "接続中のロール" do
    let(:role) do
      connection.select_one(<<~SQL)
        SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user
      SQL
    end

    # スーパーユーザー・BYPASSRLS・表の所有者のどれかで接続すると、RLS を抜きにテストが通ってしまう
    it "スーパーユーザーでも BYPASSRLS でもない" do
      expect(role).to eq("rolsuper" => false, "rolbypassrls" => false)
    end

    it "どの表の所有者でもない" do
      owned = connection.select_values(<<~SQL)
        SELECT relname FROM pg_class
        WHERE relnamespace = 'public'::regnamespace AND pg_has_role(current_user, relowner, 'USAGE')
      SQL

      expect(owned).to be_empty
    end
  end

  it "テナントの表はすべて ENABLE と FORCE の RLS を持つ" do
    without_rls = connection.select_values(<<~SQL)
      SELECT relname FROM pg_class
      WHERE relnamespace = 'public'::regnamespace
        AND relname IN (#{tenant_tables.map { |table| connection.quote(table) }.join(", ")})
        AND NOT (relrowsecurity AND relforcerowsecurity)
    SQL

    expect(without_rls).to be_empty
  end

  it "テナントの表はすべて、所有テナントに限る owner_write のポリシーを持つ" do
    policies = connection.select_rows(<<~SQL).to_h
      SELECT tablename, cmd || ' ' || qual || ' ' || with_check FROM pg_policies
      WHERE schemaname = 'public' AND policyname = 'owner_write' AND permissive = 'PERMISSIVE'
    SQL
    expected = "ALL (owner_tenant_id = current_tenant_id()) (owner_tenant_id = current_tenant_id())"

    expect(tenant_tables.index_with { |table| policies[table] }).to eq(tenant_tables.index_with { expected })
  end

  it "テナントの表はすべて、子の複合外部キーが参照する UNIQUE (owner_tenant_id, id) を持つ" do
    with_unique = connection.select_values(<<~SQL)
      SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
      WHERE c.relnamespace = 'public'::regnamespace AND i.indisunique
        AND ARRAY['owner_tenant_id', 'id']::name[] = (
          SELECT array_agg(a.attname ORDER BY k.ord)
          FROM unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.attnum
        )
    SQL

    expect(tenant_tables - with_unique).to be_empty
  end

  # 親だけを参照する外部キーだと、相手テナントの親を指す子を DB が通してしまう
  it "テナントの表どうしの外部キーは、owner_tenant_id を含む複合外部キーである" do
    single_column = connection.select_values(<<~SQL)
      SELECT con.conname FROM pg_constraint con
      WHERE con.contype = 'f'
        AND EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = con.conrelid AND attname = 'owner_tenant_id')
        AND EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = con.confrelid AND attname = 'owner_tenant_id')
        AND NOT EXISTS (
          SELECT 1 FROM pg_attribute
          WHERE attrelid = con.conrelid AND attname = 'owner_tenant_id' AND attnum = ANY (con.conkey)
        )
    SQL

    expect(single_column).to be_empty
  end
end
