# 品目の単位は画面に並べる日本語の列なので、名前の列と同じく、流用元の Intl.Collator("ja") と同じ規則で並べる ja-x-icu にする
# （docs/architecture/data-model.md「文字列の照合順序」）。DB の既定の照合順序はイメージの initdb で決まり、en_US.utf8 では
# 単位がコードポイントの順（本が箱より先）に並んで、流用元と変わる
class SetItemUnitCollation < ActiveRecord::Migration[8.1]
  # 照合順序を変えると、表を ACCESS EXCLUSIVE でロックする。unit を含む索引は無いので、作り直す索引は無い。
  # strong_migrations 2.8 は長さを変えない varchar の型の変更を安全に数え、照合順序を見ないので止めない。
  # 表は小さく、公開の配置は毎日 DB ごと作り直すので、このロックを許す（docs/adr/001）
  def up
    change_column :items, :unit, :string, collation: "ja-x-icu"
  end

  def down
    change_column :items, :unit, :string, collation: "default"
  end
end
