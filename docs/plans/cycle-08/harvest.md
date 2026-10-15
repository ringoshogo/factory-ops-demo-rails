# サイクル 08 の知見の収穫

サイクル 08（M51・M50 の残り・M33 の残り）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 9ae7462..b15b213`）、振り返りの想定外（`retrospective.md`）、改善の候補（IB-131〜IB-137）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`・`showcase.md`・`deploy/README.md`・`handoff.md`）である。diff の層ごとの読み取りは、取りまとめ役とも実装者とも別の Codex に `b15b213` の版を展開したディレクトリで頼み、結果をファイルと行で確かめてから書いた。マイルストーンの中で正本に書き足した分（`testing.md`「行列テストとの分担」の待ちの上限と around の送出の後の巻き戻し、`config.md` の一時の DB の名前と E2E の読み込みの変数と `publish` の `success()`、`bin.md` の一時の DB のタスク、`dev-cycle.md`「着手の前に」、`graphql-schema.md` の空の `thenBy` と単位の並び、`data-model.md`「文字列の照合順序」、`context-map.md`「発注の連結と品番の照合」の取消の文言、`packs-and-packwerk.md`、`README.md`、`handoff.md`「開発環境」）は済んでいるので、ここではその漏れを拾った。

漏れの中心は、サイクル 06・07 と同じく見せどころ（`showcase.md`）である。M51 の仕組みはどのテーマにも載っておらず、テーマ 10 には `publish` の `if:` の前の形が残っていた。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| CI と設定 | `publish` の `if:` に `success()` を明示し、`needs` の失敗・取消・skip で止める守りを YAML の行で読めるようにしたこと | 作り方 | 古い。テーマ 10 の公開の配置の箇条が「状態の関数を書かず、GitHub が足す `success()` が止める」のままだった | `showcase.md`「10. 運用性」の公開の配置の箇条・確かめ・状態 | `b25971d` |
| テスト | ポリシーの足し外しの待ちの上限と打ち切りの診断、around の送出を example の失敗に移して巻き戻す補助。1 つの example の失敗で後ろのグループが止まらないこと | 作り方 | 無い。規則は `testing.md`「行列テストとの分担」にあり、見せどころのテーマ 9 に無かった | `showcase.md`「9. テスト戦略」のどこで守っているか・状態 | `d25b9f1`・`1edb62b` |
| テスト・CI と設定 | 手元の E2E の Rails も CI と同じく起動の時に読み込むこと | 作り方 | 無い。変数は `config.md`「環境ごとの設定」と `README.md` にあり、見せどころの画面の E2E の箇条に無かった | `showcase.md`「9. テスト戦略」の画面の E2E の箇条・状態 | `5a3c2af` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | 品目の単位も `ja-x-icu` にし、個 < 箱 < 本に並べること | 正本にある（`data-model.md`「文字列の照合順序」、`graphql-schema.md`「ページングと N+1」、`showcase.md`「6. GraphQL の安全な形」。M50 の残りで直した） |
| 配置 | PostgreSQL のイメージを上げたときの照合順序の版の改め方 | 正本にある（`config.md`「照合順序の版」、`deploy/README.md`）。名前と単位の両方に直してある |
| 公開 API・ジョブとイベント | 変更なし | diff に公開 API・イベント・ジョブの変更が無い |
| policy | 本番の policy の変更なし | テストの DB にだけ足すポリシーの待ちは、上の表のテストの行で見せどころに載せた |
| GraphQL | `orderBy` を省いた `thenBy: []` を省いたときと同じに扱い、空でない `thenBy` だけをエラーにすること | 正本にある（`graphql-schema.md`「ページングと N+1」。OI-202 で直した） |
| テスト | 待ちの上限の値（2 秒）、打ち切りのメッセージの読み方、`remove!` の後に残ったポリシーを外すコマンド | 正本にある（`testing.md`「行列テストとの分担」） |
| テスト | 診断の SQL、セーブポイント、rspec-core の include の順、直の呼び出しを止める example の名指しの外し方 | 実装の手段。`spec/support/matrix_cross_read.rb`・`around_hook_errors.rb`・`spec/matrix/cross_read_spec.rb` のコメントにある |
| テスト | ログインの後の URL の期待にだけ 20 秒を渡すこと | 実装の手段で、`frontend/e2e/support/world.ts` のコメントに理由がある。値の決め方は計画の M51 の作るもの 2 と証跡にあり、作者の確認は OI-206（`judgment`）で待つ |
| 開発の道具 | 一時の DB の一覧と削除のタスクの呼び方・名前の規則・拒む DB・`FORCE` なし | 正本にある（`bin.md`「bin/rails で流す運用のタスク」、`config.md`「database.yml：同じ DB に 2 つのロールで接続する」、`README.md`、`handoff.md`「開発環境」）。見せどころには載せない。開発の道具で、設計判断を示すテーマに当たらない |
| 開発の道具 | 取りまとめ役が担当を止めるときに、その担当の一時の DB を消すこと | 正本にある（`dev-cycle.md`「着手の前に」） |
| 画面 | 取り消した伝票の明細の行に「品番未照合（取消）」「未確定（取消）」と出し、受注側では注意の色にしないこと | 正本にある（`context-map.md`「発注の連結と品番の照合」）。見せどころには、合計の欄の「取消」（サイクル 07）も載せておらず、画面の文言の規則はテーマに当たらない |
| 引き継ぎ | `handoff.md`「決まっていないこと」の一覧の並べ替えの行が、品目の単位と `publish` の書き方を作者の判断待ちと書く。「次にやること」が M51 の計画レビューから始めると書く | 古い。台帳の棚卸しで、サイクル 08 の終わりの形に直した（`inventory.md`） |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 単位の照合順序のマイグレーション、`structure.sql`、`collations_spec.rb`、`data-model.md` | 無し |
| 公開 API | diff に変更なし | 無し |
| policy | diff に本番の変更なし。テストの `MatrixCrossRead` | 見せどころのテーマ 9 の箇条 |
| GraphQL | `Resolvers::SortArguments`、`spec/requests/catalog_spec.rb`、`graphql-schema.md` | 無し |
| ジョブとイベント | diff に変更なし | 無し |
| テスト | `cross_read_spec.rb`、`around_hook_errors_spec.rb`、`temp_databases_spec.rb`、`ci_checks_spec.rb`、`rails_helper.rb`、2 つの補助、`testing.md` | 見せどころのテーマ 9 の箇条 |
| CI と設定 | `.github/workflows/ci.yml`、`config/environments/test.rb`、`config.md`、`packs-and-packwerk.md` | 見せどころのテーマ 10 の公開の配置 |
| 画面 | 受注と発注の詳細、`format.ts` と単体、`list-pagination.spec.ts`、`start-rails.sh`、`world.ts` | 見せどころのテーマ 9 の画面の E2E の箇条 |
| 配置 | `deploy/README.md` の照合順序の版の手順 | 無し |
| 見せどころ・README・引き継ぎ | `showcase.md` 全体、`README.md` の開発環境と画面、`handoff.md` | 見せどころの 3 行。`handoff.md` は棚卸しで直した |

## 前の形の数え上げ

振る舞いを変えた後の前の形を、`b15b213` の版で数えた（`docs/plans/` を除く。証跡は書いた時点の記録なので数えない）。件数は当たった行の数である。

| パターン | 件数 | 読み |
|---|---|---|
| `暗黙の` と `success()` が同じ行 | 4 | `handoff.md` の M48 の要約（その時点の形）と、計画の M42・M48・M51 の節（直す対象の説明）。正本とコードに 0 件 |
| `状態の関数を書[かき]` | 4 | `showcase.md` のテーマ 10 の 1 件が古く、上の表で直した（直した後は 0 件）。計画の 3 件は M48 の節と、M51 の直す対象の説明 |
| `` `orderBy` を省いて `thenBy` を渡す `` | 1 | 計画の M47 の節。M51 の節が空の配列を区別すると書き、正本（`graphql-schema.md`）は直してある。閉じたマイルストーンの記録なので直さない |
| `画面に並べる名前の列` | 2 | 計画の M49 の節（その時点の範囲）と、M50 の残りの直す対象の説明。正本は「画面に並べる日本語の列」に直してある |
| `同じ順位の名前` | 0 | — |
| `品番照合待ち`（正本の `architecture/`） | 12 | 状況とイベントの名前と、取り消していない伝票の規則。`context-map.md` の明細の行の段落は取消の場合を書き分けている |
| `上限が無[いく]` | 6 | `matrix_cross_read.rb` と `testing.md` は上限を置く理由の説明、計画は RED の説明、ほかの 3 件は別の上限。ポリシーの足し外しに上限が無いと書く文は 0 件 |
