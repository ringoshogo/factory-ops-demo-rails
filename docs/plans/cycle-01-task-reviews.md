# サイクル 1 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No Go のどれかである。

## M15 コメントの規約と掃除

PR #22。どちらの系統も Conditional Go で、指摘はすべて同じブランチの commit で直した。

| 系統 | 判定 |
|---|---|
| Codex | Conditional Go |
| Claude | Conditional Go |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex | Cop の spec が、コメントの解析の境界を守っていない。`=begin`／`=end` を無視するように Cop を壊しても spec が全件通る | 連続する `#` 行と `=begin`／`=end` の中の語を落とす例、文字列・ヒアドキュメントの中の `#` とマジックコメントを通す例を足した。`=begin`／`=end` を無視するように Cop を壊すと spec が落ちることを確かめてから戻した | `2093fb6` |
| Medium | Claude | 「出荷停止中は導出しない」に理由が無く、`data-model.md` の導出表（出荷停止中の行）と食い違って見える（`shipment_request_status.rb`・`shipment_request_status_type.rb`・`shipment_request_status_spec.rb`） | 出荷停止を記録する表（`shipping_holds`）が無いので導出しない、という今の理由を書いた | `1b12b73` |
| Low | Claude | コメントが参照する節名が、見出しの表記（「在庫（`inventory`）」「出荷（`fulfillment`）」）と違う | 見出しどおりバッククォート付きにし、見出しの文字列で grep して当たることを確かめた | `1b12b73` |
| Low | Claude | PR の本文に、完了条件を計画から変えた点が書かれていない | PR の本文に、git grep を合否から外して `bin/rubocop` と Cop の spec に一本化したことと、経緯の語「直した」を「を直した」に絞ったことを書いた | PR の本文 |
