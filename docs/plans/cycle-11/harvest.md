# サイクル 11 の知見の収穫

サイクル 11（M58）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff 964d4e1..41b601c`）、振り返りの想定外（`retrospective.md`）、改善の候補（IB-154・IB-156〜IB-160）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`・`showcase.md`・`deploy/README.md`・`handoff.md`）である。サイクルの diff は `docs/` を除いて 7 ファイル・+85／−27 行と小さいので、層ごとの読み取りは取りまとめ役の側で行った。マイルストーンの中で正本に書き足した分（`guides/config.md` の規則 3 と 3 つの規則の前置き、`guides/testing.md`「層への配分」の乱順の 1 文、`showcase.md` のテーマ 10 の列を消す変更の箇条と「状態」）は済んでいるので、ここではその漏れを拾った。

漏れは、サイクル 06〜10 と同じく見せどころ（`showcase.md`）だった。M58 で足した乱順とそのガードが、テスト戦略のテーマ 9 に無かった。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| テスト | spec は乱順で流れ、落ちたら出力の seed で同じ並びと同じ `Kernel.rand` で流れ直すこと。乱順が既定であることを、親のプロセスではなく何も渡さずに流す子のプロセスで確かめ、その理由がコマンドラインの `--seed` が設定より優先することであること | 作り方 | 規則は `guides/testing.md`「層への配分」にあり、ガードの形と理由は `spec/platform/spec_order_spec.rb` のコメントにある。見せどころのテーマ 9 の「どこで守っているか」に無かった | `showcase.md`「9. テスト戦略」に箇条 1 つ、状態に M58 | `5bb8dc7`・`934267a` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | `Sales::Item` の `unit_price` の `ignored_columns` を外し、マイグレーションのコメント 1 行を消したこと | 正本にある（`guides/config.md` の規則 3）。見せどころのテーマ 10 も M58 で直した |
| 表とマイグレーション | `reset_column_information` が schema cache の表の分を消してモデルに列を読み直させ、接続の `clear_cache!` は準備した文を捨てるだけであること | 正本にある（`guides/config.md` の規則 3 の理由。M58 で計画の原文を写した） |
| 公開 API | `Imports::Import::KINDS` を消したこと | 使い手の無い定数を消しただけで、取り込みの種類を `Imports::CsvFormat::COLUMNS` のキーが持つことは、M57 の enum の一致の spec の表とコードが語る |
| テスト | 移行の spec の後始末を 1 つのメソッドに出し、2 回呼んでも同じ形に戻すこと。`describe` の局所変数を読むので `define_method` で定義したこと | 実装の手段。後始末を確かめる形の理由は spec のコメントにあり、規則は `config.md` の規則 3 にある |
| テスト | 子のプロセスを `--options .rspec` で流し、`SPEC_OPTS`・`COVERAGE`・`FULL_SUITE` を外して渡すこと。流す対象を `_spec.rb` で終わらない名前で `spec/fixtures/` に置くこと | 実装の手段。理由は `spec/platform/spec_order_spec.rb` と `spec/fixtures/spec_order/examples.rb` のコメントにあり、`spec/fixtures/` に置く前例（`public_api_returns/one_example.rb`）と同じ形である |
| テスト | 子が `.rspec` の `--require packs/rails/rspec` で packs-rails の統合も読むこと | 改善の候補 IB-160 にあり、改善の探索で扱う。正本に書くかを決めていないので、ここでは書かない |
| テスト | `Kernel.srand config.seed` の利点が、いまのコードでは小さいこと | 改善の候補 IB-159 にあり、改善の探索で扱う |
| CI と設定 | 積み重ねたブランチで手元の `bin/ci` の `BASE_REF` に前の段のブランチを渡すと、前の段のマージでブランチが消えて落ちること | 振り返りの想定外 1 で、回し方の手順の欠けなので再発防止で扱う（知見ではない） |
| 画面 | 変更なし | — |
| 配置 | 変更なし。`unit_price` を消すマイグレーションは M27 で main に入っているので、`ignored_columns` を外す時機の規則 2 に当たらない | 正本の規則 2 のとおりで、計画の「判断」に書いてある |
| 引き継ぎ | `handoff.md`「次にやること」と「ブランチ」 | 知見ではなく引き継ぎの更新で、台帳の棚卸しでサイクル 11 の終わりの形に直す（`inventory.md`） |

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | `db/migrate/20261012200100_remove_unit_price_from_items.rb` のコメント、`item.rb`、`structure.sql`（変更なし）、`guides/config.md` の 3 つの規則 | 無し |
| 公開 API | `packs/imports/app/models/imports/import.rb`、`Imports::CsvFormat::COLUMNS`、`spec/graphql/enum_values_spec.rb` の取り込みの種類の行 | 無し |
| policy | 変更なし | 無し |
| GraphQL | 変更なし | 無し |
| ジョブとイベント | 変更なし | 無し |
| テスト | `spec/spec_helper.rb`、`spec/platform/spec_order_spec.rb`、`spec/fixtures/spec_order/examples.rb`、移行の spec、`.rspec`、`guides/testing.md` | 見せどころのテーマ 9 |
| CI と設定 | `.github/workflows/ci.yml`・`config/ci.rb`（変更なし。CI は `--seed` を渡さないので、乱順の既定で流れる）、`guides/config.md`「CI の工程」 | 無し |
| 画面 | 変更なし | 無し |
| 配置 | `deploy/README.md`（変更なし） | 無し |
| 見せどころ・README・引き継ぎ | `showcase.md` 全体、`README.md` の開発環境の `bundle exec rspec`（乱順で流れることは `testing.md` が書く）、`handoff.md` | 見せどころの 1 か所。`handoff.md` は棚卸しで直す |

## 前の形の数え上げ

振る舞いを変えた後の前の形を、`41b601c` の版で数えた（`docs/plans/` を除く。証跡は書いた時点の記録なので数えない）。件数は当たった行の数である。

| パターン | 件数 | 読み |
|---|---|---|
| `ignored_columns`（`packs`） | 0 | M58 の完了条件 |
| `外さず`・`順を乱しておらず`・`ignored_columns でこの列`（`docs`・`packs`・`db`、計画を除く） | 0 | M58 の完了条件 |
| `Import::KINDS`・`KINDS = %w[items stocks]`（`packs`・`spec`・`app`・`lib`） | 0 | M58 の完了条件 |
| `外さず`・`順を乱しておらず`（`docs/implementation-plan.md`） | 4 | M58 の節の完了条件と「文書に残すこと」の 2 行（前の形を名指しする）、M54 の「残り（サイクル 10）」の規則 3（M58 で替えたことを括弧で書き足した当時の計画）、M37 の節の別の意味の「外さず」 |
| `生成器の注釈`・`=begin`（`docs`、計画を除く） | 1 | `handoff.md`「リポジトリの状態」の実装の行の、サイクル 10 の改善の探索で見つけたことの記録（過去の発見として書き、続く M58 の記録が乱順にしたことを書く）。いまの設定を注釈の中にあると書く文は残っていない |
