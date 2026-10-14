# サイクル 7 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M48 CI で依存の木を確かめ、イメージの組み立てを PR のたびに流す

`m48-ci-deps-check`（base は `main`、PR #84）。サイクル 07 の計画の `cycle-07-decisions` の先端 `8ad4320` から切った。計画の PR #83 が未マージの間は、その commit も PR の差分に見える。M48 の差分は `8ad4320..` である。

Codex も Claude も Go だった。どちらの系統も、`8ad4320..302dfb7` の diff を `302dfb7` の版で読んだ。Claude は証跡の `publish` の 3 つの実行を `gh run view` で読み、表と一致することを確かめ、ワークフローの写しを壊して spec と同じ判定を流した。Codex は GitHub の実行を読めず、証跡を前提にし、spec をワークフローの壊し方を替えて手元で流した。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

指摘は 6 件で、どれも、壊しても `ci_checks_spec.rb` が落ちない壊し方（Claude R1・R2、Codex R1・R2）か、前の形を書いた文（Claude R3、Codex R3）だった。壊しても落ちない 4 件は、`publish` が `needs` の失敗を待たなくなるか、`npm ls --all` が入れた木を読まなくなる壊し方で、M48 が守りを暗黙の `success()` に移したことで重みが増した。spec を直し、下の壊して落ちる記録に、指摘の壊し方の行を足した。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Medium 2・Low 1） | 出していない（High が無かった） |
| Claude | Go（Medium 1・Low 2） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘なし |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘（R3） |
| テストの検出力 | 指摘（R1・R2） | 指摘（R1・R2） |
| 参照の維持 | 指摘（R3） | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Claude | R1：`publish` の守りは `if:` に状態の関数が無いことだけになったが、`if:` を `always() && ...` か `!cancelled() && ...` に替えても spec が通る。その形では `test` が落ちた main の commit のイメージを置く | `if:` の example に、`publish` の `if:` が状態の関数（`success`・`failure`・`cancelled`・`always`）を含まないことの期待を足した。式の形ではなく、含まないことだけを照らす。`guides/config.md`「CI の工程」の spec が確かめることの列挙と、spec で守らないものの段落の例外に書いた | この節を載せた commit |
| Medium | Codex | R1：`needs` を不足だけで照らすので、`needs` に無いジョブの名前（`audit`）を足しても落ちない。証跡の「`needs` に無いジョブ `audit` を足す」の行と食い違って読める | `needs` をほかのすべてのジョブと集合で等しいかで照らし、不足・余分・重複を落とす形にした。証跡の行は、ワークフローにジョブを足した壊し方で、`needs` に名前を足した壊し方とは別だったので、行の名前を書き分け、`needs` に名前を足す行を足した | 同上 |
| Medium | Codex | R2：`npm ls --all` のステップの `working-directory` だけを見て、ジョブの既定（`defaults.run.working-directory`）を根に替えるか消しても落ちない | `npm ci` と `npm ls --all` の実際の置き場（ステップの `working-directory` か、無ければジョブの既定）が、どちらも `frontend` であることを照らす形にした | 同上 |
| Low | Claude | R2：ジョブの段の `continue-on-error` だけを見て、`test` の `Run tests` などのステップの段の `continue-on-error: true` で落ちない | `needs` の example の `continue-on-error` の確かめを、すべてのジョブとすべてのステップに広げた。`npm ls --all` の example からは、重なる `continue-on-error` の確かめを外した。`config.md` の文もステップの段に広げた | 同上 |
| Low | Claude | R3：`if:` の example のコメントが、ほかのジョブに契機を絞る `if:` を足すと「確かめないまま push する」と、M42 の形の帰結を書いている | M48 の形の帰結（push でそのジョブが skip され、`publish` も skip されてイメージが置かれない）に直した | 同上 |
| Low | Codex | R3：計画の M33 の CI の一覧に `npm ls --all` が無く、M44 の #70 の行が「CI は `npm ls --all` を流さない」と今の形で書く | M44 の行を「M44 の時点の CI は流さなかった。M48 で足した」と時点を書いた。M33 の節は M33 で作ったものの記録で、M42 の節の `image_inputs` と同じく書き換えない | 同上 |

違和感は次のように扱った。

- Claude 1：OI-184 の内容の欄が M42 の形を今の形として書いたまま残る → IB-116
- Claude 2：計画の M44 の節の表が「CI は `npm ls --all` を流さない」と今の形で書く → Codex R3 と同じく直した
- Claude 3：`config.md`「CI の工程」の spec で守らないものの段落に、M48 の `npm ls --all` の example が照らす順と引数の例外が書かれていない → 同じ段落に、壊れると確かめないまま通す規則は含む・含まないの条件で照らす例外として書いた
- Claude 4：`continue-on-error` の行が GREEN の後に足したと分かる書き方で、記録の形に問題は無い → 扱うことは無い
- Codex：なし

IB-17 の試行の効いたとする基準のうち、壊して落ちる記録に「消す」以外の型の行が足すか直した example のそれぞれに 1 つ以上あることは満たした。実装レビューの観点 4 の「壊しても落ちない」指摘が 2 系統とも 0 件であることは満たさなかった（Claude 2 件、Codex 2 件）。4 件とも、担当が試行で流した壊し方の型（値を替える・書き込み先を替える・要素を足す）の、別の対象（`publish` の `if:` の値、ジョブの既定の置き場、`needs` の名前、ステップの段の `continue-on-error`）だった。サイクル 07 の末の振り返りで、サイクル 06 の件数と比べる。

### 実装の記録

#### 計画との違い

- `publish` の `skipped` の守り（作るもの 3）は、計画の `!contains(needs.*.result, 'skipped')` の項をジョブの段に戻す形ではなく、`if:` を `github.event_name == 'push'` だけにし、状態の関数を書かずに GitHub が足す暗黙の `success()` に任せる形にした（`38864fb`）。`success()` は `needs` のどれかが落ちた・取り消された・skip されたときに偽になるので、`!cancelled()` と `failure`・`cancelled`・`skipped` の 3 つの項を並べた式と同じ守りになる。M42 で `!cancelled()` を要したのは、push で skip される `image_inputs` が `success()` を偽にしたからで、`image_inputs` を外せばその理由が無くなる。確かめ方は下の「`publish` の条件」にある。計画の M48 の作るもの 3 と `guides/config.md`「CI の工程」を直し、OI-184 の結果の欄に書いた。
- `ci_checks_spec.rb` の `needs` の example に、`continue-on-error` を持つジョブが無いことの確かめを足した。壊し方の型の試行（作るもの 4）で、`images` にジョブの段の `continue-on-error: true` を足しても何も落ちず、そのジョブが落ちても `needs` の結果は `success` になり、`publish` がそのジョブの成功を待たなくなるからである。実装レビュー（Claude R2）で、ステップの段にも広げた。`guides/config.md`「CI の工程」に書いた。
- 計画の「文書に残すこと」の外で、`README.md`「画面」の検査のコマンドに `npm ls --all > /dev/null` を足した。CI の `frontend` のジョブと同じ検査を手元で流す手順だからである。
- 「`image_inputs`」は、`git grep` で `implementation-plan.md`（M42・M48 の節と前提の表）と `docs/plans/` のほかに 0 件である。`adr/009`「見直す条件」は、戻すときの形を名前を使わずに「M42 で作り M48 で外した、PR が変えたファイルで判定するジョブ」と書いた。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：`spec/platform/ci_checks_spec.rb` に `npm ls --all` の example を足し、`needs` と `if:` の example の期待を外した後の形に直し、ワークフローを変える前（`8ad4320` の作業ツリー）に流した（8 examples, 3 failures）。

- `npm ls --all` の example：`expected ["npm run codegen:check", "npm run lint", "npm run typecheck", "npm run test:unit"] to include "npm ls --all"`
- `publish` の `needs` の example：`expected: [] got: ["image_inputs"]`
- ジョブの段の `if:` の example：`expected: ["publish"] got: ["image_inputs", "images", "publish"]`

`continue-on-error` の確かめと、実装レビューで足した確かめ（`publish` の `if:` の状態の関数、`needs` の余分、ジョブの既定の置き場）は GREEN の後に足したので、下の壊して落ちる記録で RED に代える。

ワークフローを 1 か所ずつ壊し、`bundle exec rspec spec/platform/ci_checks_spec.rb` を流して、ワークフローの複製から戻した（実装レビューの直しを載せた版で。8 examples）。壊し方の型は IB-17 の試行の分類で、「消す・外す」のほかの型を、足すか直した example のそれぞれに 1 つ以上置いた。「実装レビュー」の行は、実装レビューの指摘の壊し方で、直す前の spec（`302dfb7`）では落ちなかった。

| 確かめる example | 壊し方の型 | 壊したもの | 落ちたもの |
|---|---|---|---|
| `npm ls --all` | 消す | `npm ls --all` のステップを消す | 1（この example） |
| 〃 | 順を入れ替える | ステップを `npm ci` の前に動かす | 1（同上） |
| 〃 | 外す | 引数から `--all` を外す | 1（同上） |
| 〃 | 値を替える | 引数を `--depth=0` に替える | 1（同上） |
| 〃 | 条件を足す | ステップに `if: false` を足す | 1（同上） |
| 〃 | 書き込み先を替える | ステップの `working-directory` を根（`.`）に替える | 1（同上） |
| 〃 | 書き込み先を替える（実装レビュー） | ジョブの既定の `working-directory` を根（`.`）に替える | 1（同上） |
| 〃 | 消す（実装レビュー） | ジョブの既定の `working-directory` を消す | 1（同上） |
| `publish` の `needs` と `continue-on-error` | 消す | `needs` から `manifests` を消す | 1（この example） |
| 〃 | 値を替える | `needs` の `manifests` を `images` に替える（重複） | 1（同上） |
| 〃 | 要素を足す | ワークフローに、`needs` に無いジョブ `audit` を足す | 1（同上） |
| 〃 | 要素を足す（実装レビュー） | `needs` に、無いジョブの名前 `audit` を足す | 1（同上） |
| 〃 | 要素を足す | `images` にジョブの段の `continue-on-error: true` を足す | 1（同上。この確かめは GREEN の後に足したので、これで RED に代える） |
| 〃 | 要素を足す（実装レビュー） | `test` の `Run tests` にステップの段の `continue-on-error: true` を足す | 1（同上） |
| 〃 | 要素を足す | `npm ls --all` のステップに `continue-on-error: true` を足す | 1（同上） |
| ジョブの段の `if:` と `publish` の `if:` | 条件を足す | `images` に `if: github.event_name == 'pull_request'` を足す | 1（この example） |
| 〃 | 条件を足す | `e2e` に `if: always()` を足す | 1（同上） |
| 〃 | 消す | `publish` の `if:` を消す | 1（同上） |
| 〃 | 値を替える（実装レビュー） | `publish` の `if:` を `always() && github.event_name == 'push'` に替える | 1（同上） |
| 〃 | 条件を足す（実装レビュー） | `publish` の `if:` に `!cancelled() &&` を足す | 1（同上） |

`pattern` の example は、`image_inputs` のジョブと一緒に消した。`publish` の `if:` の式と、ログイン・push のステップの `if:` は、spec で守らない（`../../guides/config.md`「CI の工程」の、YAML の式を文字列で照らさない方針）。下の「`publish` の条件」の、ブランチへの push で確かめた。

### 確かめたこと

#### `npm ls --all` のステップ

PR #84 の CI で、2 つの木で流した。

| 回 | commit | `npm ci`（Install dependencies） | `npm ls --all`（Check dependency tree） | `frontend` |
|---|---|---|---|---|
| いまの木 | `38864fb` | 成功 | 成功 | 成功（50 秒） |
| `eslint` を 10 に上げた木（一時の commit） | `66df546` | 成功 | 失敗（`npm error code ELSPROBLEMS`、`invalid: eslint@10.12.0`。`eslint-config-next` の下の `eslint-plugin-import`・`eslint-plugin-jsx-a11y`・`eslint-plugin-react` の peer の範囲が `^9` まで）。後のステップは流れなかった | 失敗 |

実行の URL：[`38864fb`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38497200478)、[`66df546`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38497588113)。`66df546` の木は、`frontend/package.json` と `package-lock.json` の写しに `npm install --package-lock-only -D eslint@^10` を流して作った（#70 と同じ `eslint` 10 への上げ）。手元でも、その木で `npm ci` は通り、`npm ls --all` は終了コード 1 で終わった。`66df546` のほかのジョブはすべて成功した。`31eceb5` で 2 つのファイルを戻した。

#### `images` の時間

ワークフローの時間は、実行が始まってから終わるまでで、どの回も `test` のジョブが最も長かった。

| 回 | commit | `images` | 内訳 | ワークフロー |
|---|---|---|---|---|
| 最初の PR の CI（キャッシュが効く） | `38864fb` | 1 分 9 秒 | Rails のイメージ 39 秒・起動 2 秒・画面のイメージ 10 秒 | 4 分 6 秒 |
| キャッシュが空（`scope` を `api-m48-cold`・`frontend-m48-cold` に替えた一時の commit） | `31eceb5` | 3 分 41 秒 | Rails のイメージ 1 分 47 秒・起動 2 秒・画面のイメージ 1 分 34 秒 | 6 分 5 秒 |

実行の URL：[`38864fb`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38497200478)、[`31eceb5`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38498086385)。どちらの回も、ワークフロー全体が 10 分の内に終わった。`scope` は `bfe7d78` で戻した。

#### `publish` の条件（M48 のブランチへの push）

`publish` は main への push でしか流れないので、`bfe7d78` でワークフローの `on.push.branches` に `m48-ci-deps-check` を足し、ブランチへの push で確かめた。push は force push を挟まずに続けた。どの push でも、同じ commit の PR の実行が別に流れ、`publish` は `github.event_name` で skip された。

| push | commit | ほかのジョブ | `publish` |
|---|---|---|---|
| `manifests` に `if: false` を足した（`ci_checks_spec.rb` の `if:` の example の期待も一時に `manifests` を含めた） | `bfe7d78` | `manifests` が skip、ほかは成功 | skip |
| `if: false` を外した | `75f7476` | すべて成功 | 流れて成功（50 秒）。ログインと push のステップは skip |
| `ci_checks_spec.rb` に落ちる example を 1 つ足した | `502cab5` | `test` だけが落ちた（2982 examples, 1 failure、足した example）。ほかは成功 | skip |

実行の URL：[`bfe7d78`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38498666421)、[`75f7476`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38499215373)、[`502cab5`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38499713257)。

skip された `needs` で止まる側と、すべて成功したときに誤って止めない側の 2 つがそろったので、ジョブの段に戻した形のままにし、最初のステップは消したままにした（OI-184）。`67c4e17` で一時の commit を戻し、`on.push.branches` は `[ main ]` だけになった。`38864fb` からのワークフロー・spec・画面の依存の差分は無い。

M48 をマージした後の最初の main への push で `publish` が流れ、2 つのイメージを置くことは、取りまとめ役がサイクル 07 の振り返りで確かめる（計画の M48 の完了条件）。

#### 手元で流したもの

`38864fb` の作業ツリーで、Ruby 3.4.11・PostgreSQL 18 で流した。

```sh
bundle exec rspec spec/platform/ci_checks_spec.rb spec/platform/dependency_updates_spec.rb   # 18 examples, 0 failures
bin/ci                                              # すべての工程が通った。rspec は 2981 examples, 0 failures
cd frontend && npm ci && npm ls --all > /dev/null   # 終了コード 0（Node 22.23.3）
```

分岐の網羅率の警告は 0 件だった（M48 は Ruby のアプリのコードを変えていない）。この節と台帳と `handoff.md` を載せた版で、`bin/check-open-items --due M48` と `bin/check-commit-refs` を流して通した。

実装レビューの直しの後も、`f08f6fb` の作業ツリーで `bin/ci` を流し、すべての工程が通った（rspec は 2981 examples, 0 failures、分岐の網羅率の警告は 0 件）。`bin/check-open-items --due M48` と `bin/check-commit-refs` も通った。`f08f6fb` の PR の CI はすべて通り、ワークフローは 6 分 8 秒だった（`test` が 6 分 5 秒で最も長く、`images` は 1 分 16 秒。[実行](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38501174039)）。

### 残件の処理

引当先が M48 の行は、着手の前と PR の前に台帳を読んだ。どちらの時点でも無かった。OI-184（作者の確認で「M48 で簡単にできるかを確かめる」）の結果の欄に、M48 で戻した形と 2 つの実行の URL を書いた。IB-104・IB-113 は M48 で実装し、IB-17 の試行の標本は上の壊して落ちる記録である。IB-17 の効いたとする基準の判定の材料は、この節の冒頭の実装レビューの結果に書いた。実装レビューの違和感は IB-116 に積んだ。

## M49 文字列の列の照合順序を決め、別の DB の worktree で `bin/ci` を流せるようにする

`m49-collations`（base は `main`、PR #86）。M48 の `m48-ci-deps-check` の先端 `abc9bd6` から切った。M48（#84）は着手の後に main にマージされたので、M49 の差分は `abc9bd6..` である。

### 実装の記録

#### 計画との違い

- 完了条件の `TEST_DATABASE` の名前を `factory_ops_m49` から `factory_ops_m49_test` にした（`31a476a`）。行列の spec（`spec/support/matrix_cross_read.rb`）は、全行を読ませるポリシーを足す前に DB の名前が `_test` を区切りとして含むかを見て、含まなければ止まる。`factory_ops_m49` で流すと `packs/sales/spec/public/sales/catalog_spec.rb` の 1 件がこの拒否で落ちた。計画の完了条件、`guides/config.md`「database.yml：同じ DB に 2 つのロールで接続する」、`handoff.md`「開発環境」に名前の付け方を書いた。
- マイグレーションを `safety_assured` で包まなかった（`fc545f5`）。strong_migrations 2.8 の PostgreSQL の型の変更の判定（`StrongMigrations::Adapters::PostgreSQLAdapter#change_type_safe?`）は、長さを変えない `varchar` を照合順序を見ずに安全に数える。包まない形で `RAILS_ENV=test bin/rails runner` から照合順序を変える `change_column` を流すと、strong_migrations は止めず、アプリのロールの権限の無さで SQL が落ちた。ロックと索引の作り直しを許す理由はコメントに書いた。計画の作るもの 1 を直し、止めないことを IB-118 に積んだ。
- 照合順序の版の記録の改め方（判断「名前の列の照合順序を何にするか」の版の扱い）を、`template1` で `REFRESH VERSION` を流してから業務の DB を消して作り直す形にした。計画は、`template1` とアプリの DB で索引を作り直してから流すと書いていた。`template1` には表が無く、作り直した DB は `template1` の記録を写し、索引を新しい ICU で作るからである。作り直さずに残す DB だけを、索引を作り直してから改める形にした。計画の版の扱いを直し、OI-197（judgment）に積んだ。
- 作るもの 4 の在庫の `ITEM_NAME` の example を足すのに合わせて、既存の 2 つの example の品目名の並びの期待を `ja-x-icu` の並び（平座金が六角の 2 つより前）に直した。`spec/requests/inventory_spec.rb` の「品目コードと品目名で並べる」（RED に含めた）と、`packs/inventory/spec/public/inventory/stocks_spec.rb` の「品目コードと品目名と ID の組で並べ…」（`bin/ci` の 1 回目で落ちて見つけた。`0b3871b`）である。
- 計画の作るもの 3・4 の外で、`packs/sales/spec/public/sales/catalog_spec.rb` に、品目の一覧を品目名で 2 件ずつのページで並べる example を足した。`items.name` を並べる example が無く、3 つの名前の列のそれぞれを既定に戻して落ちる記録（完了条件）を `items.name` で取れなかったからである。検索の example は、品目の一覧（`items`）と在庫の一覧（`item_labels`）の両方に置いた。
- E2E の世界の取引先の名前（`東海産機システム株式会社 第二工場 …` と `北関東オートメーション株式会社`）は、先頭の漢字のコードポイントの順（北が先）と音読みの順（東が先）が逆の組だったので、`DemoWorld` の名前を替えなかった。
- 前の形（「`COLLATE "C"`」「照合順序 `"C"`」）は、`git grep` で証跡（`docs/plans/`）と計画の M49 の節の文書に残すことの文のほかに 0 件である。計画の M46 の節の作り直しの文は、M46 は式で照合順序を指定し、M49 で列の照合順序に移したと時点を書いた。「`en_US`」は、`data-model.md`「文字列の照合順序」の DB の既定の説明と、競合テストの言語の照合順序の例と、計画の M49 の節と証跡に残る。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：spec を足し、マイグレーションと実装を変える前（`abc9bd6` の作業ツリー）に、`log/events.log` の無い worktree で `TEST_DATABASE=factory_ops_m49_test` を渡して流した（62 examples, 5 failures）。

- `spec/platform/collations_spec.rb` の 5 つの列の照合順序：`expected: {"item_labels.code" => "pg_c_utf8", … "tenants.name" => "ja-x-icu"} got: {"item_labels.code" => "default", …}`（5 つとも `default`）
- `spec/requests/purchase_orders_spec.rb` の受注側の名前の 1 件ずつのページ：`expected: [{"orderNo" => "PO-000002", "supplier" => {"name" => "青嵐精機工業"}}] got: [{"orderNo" => "PO-000001", "supplier" => {"name" => "東和商事"}}]`
- `spec/requests/inventory_spec.rb` の品目名の並び：`expected: [["W-3", "N-2", "B-1"], 3] got: [["N-2", "B-1", "W-3"], 3]`
- `spec/requests/inventory_spec.rb` の品目名の 1 件ずつのページ：`expected: ["W-3", "N-2", "B-1"] got: ["N-2", "B-1", "W-3"]`
- `spec/platform/logging_spec.rb` の別の DB のプロセスの example：`expect(File).to exist(shared)` で `expected File to exist`（親のファイルを `log/events.log` の固定のまま、読む前にファイルがあることを期待として確かめる形にした）

`collations_spec.rb` の版の example と、検索の 2 つの example（品目と在庫）は、変える前の振る舞いと同じことを確かめるので、変える前も通った。下の壊して落ちる記録で RED に代える。`catalog_spec.rb` の品目名の並びの example は GREEN の後に足したので、同じく下の記録で RED に代える。

列の照合順序は、`factory_ops_m49_test` の表で 1 つずつ `ALTER TABLE … ALTER COLUMN … TYPE character varying COLLATE …` で壊して spec を流し、元の照合順序に戻した（`31a476a` の作業ツリー）。版は、スーパーユーザーで `pg_collation.collversion` を書き換えて流し、`pg_collation_actual_version` に戻した。`events_log_path` は、ファイルを複製してから壊し、複製から戻した。

| 確かめる example | 壊したもの | 落ちたもの |
|---|---|---|
| `item_labels_rebuild_lock_spec.rb` の `B-1`・`a-1` | `items.code` を DB の既定（`en_US.utf8`）に戻す（作り直しの式には照合順序が無い） | 1（この example。`B-1` の保存が作り直しを待たない：`expected true got false`） |
| `catalog_spec.rb` の検索（品目） | `items.code` を `"C"` にする | 1（この example。`ä-` が `Ä-1` に当たらない） |
| `inventory_spec.rb` の検索（在庫） | `item_labels.code` を `"C"` にする | 1（この example） |
| `purchase_orders_spec.rb` の受注側の名前の 1 件ずつのページ | `tenants.name` を既定に戻す | 1（この example） |
| `catalog_spec.rb` の品目名の並び | `items.name` を既定に戻す | 1（この example。`spec/requests/catalog_spec.rb` と合わせて流した） |
| `inventory_spec.rb` の品目名の並びと 1 件ずつのページ | `item_labels.name` を既定に戻す | 2（この 2 つ。`item_labels_spec.rb` と合わせて流した） |
| `stocks_spec.rb` の品目名の並び | `item_labels.name` を既定に戻す（`0b3871b` の作業ツリー） | 1（この example） |
| `catalog_spec.rb` の検索（品目） | `items.name` を `"C"` にする | 2（この example の `ａｂｃ` と、品目名の並び） |
| `inventory_spec.rb` の検索（在庫） | `item_labels.name` を `"C"` にする | 3（この example の `ａｂｃ` と、品目名の 2 つ） |
| `collations_spec.rb` の版 | `factory_ops_m49_test` の `ja-x-icu` の `collversion` を `153.0` に書き換える | 1（この example） |
| `logging_spec.rb` の別の DB のプロセス | `Platform::Logging.events_log_path` が `TEST_DATABASE` を見ずに `log/events.log` を返す | 2（この example の `not_to include("spec.other_process")` と、パスの example） |
| E2E の受注一覧の取引先の名前の並び | `db/structure.sql` の `tenants.name` から照合順序を外し、E2E の DB を作り直す | 1（`list-pagination.spec.ts` の受注一覧の example） |
| E2E の品目の一覧の名前の並び | `db/structure.sql` の `items.name` から照合順序を外す | 1（`list-pagination.spec.ts` の品目の一覧の example） |

戻した後に同じ spec を流し、すべて通った（56 examples, 0 failures）。`item_labels_rebuild_lock_spec.rb` は、戻した後に 5 回続けて流し、5 回とも通った。

### 確かめたこと

#### 公開の配置のイメージの照合順序

`deploy/postgres.yaml` の `postgres:18.6` を手元に取り、空のクラスタを起こして `template1` で引いた。手元の `compose.yaml` の `postgres:18` も同じダイジェストで、手元の DB の `SELECT version()` も同じだった。

```sh
docker pull postgres:18.6   # postgres@sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336、arm64
docker run -d --rm -e POSTGRES_PASSWORD=… postgres:18.6
psql -U postgres -d template1 -Atc "SELECT version()"
# PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
psql -U postgres -d template1 -Atc "SELECT collname, collprovider, collversion, pg_collation_actual_version(oid) FROM pg_collation WHERE collname IN ('ja-x-icu','pg_c_utf8') ORDER BY collname"
# ja-x-icu|i|153.128.46|153.128.46
# pg_c_utf8|b|1|1
```

#### E2E

`frontend` で `E2E_DATABASE=factory_ops_m49_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e` を Node 22.23.3 で流した（E2E の DB を、ほかの担当の `factory_ops_e2e` と分けた）。`31a476a` の作業ツリーで 4 回流し、`npm ci` の直後の 1 回目だけ、`admin-only.spec.ts` の 3 件がログインの後の画面の移りを 5 秒で待ち切れずに落ちた（`Received string: "http://127.0.0.1:3201/"`。同じ回の前の 2 件は 10 秒と 17 秒かかった）。`admin-only.spec.ts` だけを流し直すと 5 件とも通り、2〜4 回目は 67 passed・25 skipped だった。照合順序の変更はログインの経路に触れないので、手元の最初の実行の遅さによるものとして IB-117 に積んだ。

#### 手元で流したもの

`0b3871b` の作業ツリー（`log/events.log` の無い worktree）で、Ruby 3.4.11・PostgreSQL 18.6 で流した。

```sh
bundle exec rspec packs/sales/spec/concurrency/sales/item_labels_rebuild_lock_spec.rb packs/sales/spec/public/sales/catalog_spec.rb packs/inventory/spec/public/inventory/item_labels_spec.rb spec/requests/catalog_spec.rb spec/requests/inventory_spec.rb spec/requests/purchase_orders_spec.rb   # 54 examples, 0 failures
bundle exec rspec spec/platform/collations_spec.rb   # 2 examples, 0 failures
TEST_DATABASE=factory_ops_m49_test bundle exec rspec spec/platform/logging_spec.rb   # 29 examples, 0 failures
TEST_DATABASE=factory_ops_m49_test bin/ci   # すべての工程が通った。rspec は 2988 examples, 0 failures
```

`bin/ci` の 1 回目（`31a476a`）は、`stocks_spec.rb` の品目名の並びの期待で 1 件落ち（2988 examples, 1 failure）、`0b3871b` で直した。実装の記録を載せた `e73974b` でも `TEST_DATABASE=factory_ops_m49_test bin/ci` を流し、すべての工程が通った（2988 examples, 0 failures）。`bin/ci` の後も `log/events.log` はできなかった。分岐の網羅率の警告は 0 件だった。`bin/check-open-items --due M49` と `bin/check-commit-refs` も通った。

`e73974b` の PR の CI はすべて通った（`test` 6 分 25 秒、`e2e` 2 分 44 秒、`images` 2 分 13 秒。`publish` は PR なので skip。[実行](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38505414473)）。CI の PostgreSQL のサービスでも `collations_spec.rb` の版の example が通った。
