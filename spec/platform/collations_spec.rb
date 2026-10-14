require "rails_helper"

# 文字列の列の照合順序（docs/architecture/data-model.md「文字列の照合順序」）。DB の既定の照合順序はイメージの initdb で決まり、
# 環境ごとに変わりうるので、並びとロックの順が照合順序に依る列は、列の定義で照合順序を持つ
RSpec.describe "文字列の列の照合順序" do
  def collations(columns)
    ActiveRecord::Base.lease_connection.select_rows(<<~SQL).to_h { [ "#{_1}.#{_2}", _3 ] }
      SELECT c.relname, a.attname, co.collname
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_collation co ON co.oid = a.attcollation
      WHERE c.relnamespace = 'public'::regnamespace AND (c.relname || '.' || a.attname) IN (#{columns.map { "'#{_1}'" }.join(", ")})
    SQL
  end

  # 品目コードは、取り込みが Ruby の文字列の比べ方（バイトの順）で行ロックを取る列なので、コードポイントの順の pg_c_utf8 にする。
  # 名前は画面に並べる列なので、流用元の Intl.Collator("ja") と同じ規則で並べる ja-x-icu にする
  it "品目コードの列は pg_c_utf8、テナントと品目の名前の列は ja-x-icu を持つ" do
    expect(collations(%w[items.code item_labels.code tenants.name items.name item_labels.name])).to eq(
      "items.code" => "pg_c_utf8", "item_labels.code" => "pg_c_utf8",
      "tenants.name" => "ja-x-icu", "items.name" => "ja-x-icu", "item_labels.name" => "ja-x-icu"
    )
  end

  # ICU の版が上がると ja-x-icu の並びが変わりうる。DB が記録した版がイメージの版と違えば、docs/guides/config.md「照合順序の版」
  # の手順で記録を改める。CI と手元のイメージで、記録と実際の版が食い違わないことを確かめる
  it "ja-x-icu と pg_c_utf8 があり、DB が記録した版がイメージの版と等しい" do
    versions = ActiveRecord::Base.lease_connection.select_rows(<<~SQL)
      SELECT collname, collversion IS NOT NULL AND collversion = pg_collation_actual_version(oid)
      FROM pg_collation
      WHERE collnamespace = 'pg_catalog'::regnamespace AND collname IN ('ja-x-icu', 'pg_c_utf8')
      ORDER BY collname
    SQL

    expect(versions).to eq([ [ "ja-x-icu", true ], [ "pg_c_utf8", true ] ])
  end
end
