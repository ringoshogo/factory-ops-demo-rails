# 並びとロックの順が照合順序に依る文字列の列に、列の定義で照合順序を持たせる（docs/architecture/data-model.md「文字列の照合順序」）。
# DB の既定の照合順序はイメージの initdb で決まり、環境ごとに変わりうる。
# 品目コードは、取り込みが Ruby の文字列の比べ方（バイトの順）で行ロックを取るので、コードポイントの順の pg_c_utf8 にし、
# コードの順でロックする SQL が照合順序を書かずに同じ順になるようにする。名前は画面に並べる列なので、流用元の
# Intl.Collator("ja") と同じ規則で並べる ja-x-icu にする
class SetStringColumnCollations < ActiveRecord::Migration[8.1]
  COLLATIONS = {
    [ :items, :code ] => "pg_c_utf8",
    [ :item_labels, :code ] => "pg_c_utf8",
    [ :tenants, :name ] => "ja-x-icu",
    [ :items, :name ] => "ja-x-icu",
    [ :item_labels, :name ] => "ja-x-icu"
  }.freeze

  # 照合順序を変えると、表を ACCESS EXCLUSIVE でロックし、items の (owner_tenant_id, code) の一意索引を作り直す。
  # strong_migrations 2.8 は長さを変えない varchar の型の変更を安全に数え、照合順序を見ないので止めない。
  # 表は小さく、公開の配置は毎日 DB ごと作り直すので、このロックを許す（docs/adr/001）
  def up
    COLLATIONS.each { |(table, column), collation| change_column table, column, :string, collation: }
  end

  def down
    COLLATIONS.each_key { |table, column| change_column table, column, :string, collation: "default" }
  end
end
