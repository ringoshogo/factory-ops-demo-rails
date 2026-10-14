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

Codex も Claude も Go だった。どちらの系統も、`abc9bd6..64e3cc7` の diff を `64e3cc7` の版で読んだ。Codex は手元の DB への接続を実行の環境に拒まれ、rspec・E2E・CI は証跡の記録を前提にし、Ruby の文字列の順とコードポイントの順の一致を 10,020 個の文字列で確かめた。Claude は 200 個の文字列で `String#sort` と `ORDER BY … COLLATE pg_c_utf8` の一致を確かめ、`factory_ops_m49_test` で `item_labels.code` を既定に戻して spec を流した（R1）。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Low 1） | 出していない（High が無かった） |
| Claude | Go（Low 3） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘（R3） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘なし | 指摘（R1） |
| 参照の維持 | 指摘（R1） | 指摘（R2） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Low | Claude | R1：`item_labels.code` を DB の既定に戻しても、振る舞いを確かめる example が落ちない（在庫の `ITEM_CODE` の品目コードがどちらの照合順序でも同じ順） | `inventory_spec.rb` に、`a-4` を足して在庫を品目コードで並べると品目の一覧と同じバイトの順（`a-4` が最後）になる example を足した。`item_labels.code` を既定に戻すと落ちる行を壊して落ちる記録に足した | この節を載せた commit |
| Low | Claude | R2：`collations_spec.rb` の版の example のコメントが、計画の前の形（索引を作り直してから記録を改める）を書く | 手順の中身を書かずに `config.md`「照合順序の版」を指す形にした | 同上 |
| Low | Claude | R3：M48 の節にある「残件の処理」が無い | 下に「残件の処理」を足した | 同上 |
| Low | Codex | R1：`data-model.md` と `graphql-schema.md` が、名前の並びが `Intl.Collator("ja")` と同じになると無条件に書く。計画は spec と E2E の名前の組に限り、`Intl.Collator` が同じ順位とする文字（は／ハ、Ａ／A）の前後は PostgreSQL がバイトの順で決める | `data-model.md`「文字列の照合順序」に、同じと言える範囲（確かめた名前の組まで。ICU の版の違いと同じ順位の文字の前後は言わない）を書き、`graphql-schema.md`・`handoff.md`・マイグレーションと spec のコメントを「同じ規則で並べる」に直した。特定の名前の組を確かめる spec のコメントは、その組では同じ並びなのでそのままにした | 同上 |

違和感は次のように扱った。

- Claude 1：`data-model.md` の表が `item_labels.code` を行ロックの順を決める列に入れるが、理由は `items` の話だけ → 行の種類を「行ロックの順を決める列と、その写し」にし、写しは在庫の一覧の並びと検索を品目の一覧とそろえるためと書いた
- Claude 2：CI と手元は `postgres:18` の動くタグで、公開の配置は `postgres:18.6` に固定しており、ICU の版が別になりうる → IB-119
- Claude 3：`deploy/README.md` の作り直しの Job の名前が、同じ日に手で流していると重なる → 既存の手順（「作り直しが飛ばされた日」）と同じ付け方で、重なれば `kubectl create job` が落ちて気付くので、扱わない
- Claude 4：`handoff.md` は「`_test` で終わる」、`config.md` は「`_test` を区切りとして含める」と書く → `handoff.md` を `config.md` の言い方にそろえた
- Codex 1：`logging_spec.rb` の `ensure` の削除を外しても、次の実行の冒頭の削除が補うので何も落ちない → IB-120
- Codex 2：OI-190 の内容の欄と IB-77・IB-110 の説明に、変える前の状態が残る → IB-116（M48 で積んだ、`decided` の行の内容の欄が前の形を今の形として書く）と同じ種類として、IB-116 で扱う

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
| `inventory_spec.rb` の品目コードのバイトの順（実装レビューの Claude R1 で足した） | `item_labels.code` を既定に戻す（直しを載せた版で） | 1（この example。`a-4` が先に来る） |
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

実装レビューの直しの後も、`66ff186` の作業ツリーで `TEST_DATABASE=factory_ops_m49_test bin/ci` を流し、すべての工程が通った（rspec は 2989 examples, 0 failures、分岐の網羅率の警告は 0 件）。`bin/check-open-items --due M49` と `bin/check-commit-refs` も通った。`66ff186` の PR の CI はすべて通った（`test` 5 分 31 秒、`e2e` 3 分 2 秒。[実行](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38506018083)）。

### 残件の処理

引当先が M49 の行は、着手の前と PR の前と実装レビューの直しの前に台帳を読んだ。OI-190（`decided`、名前の列を `ja-x-icu` にする作者の判断）は作るもの 1・4 で反映した。IB-77（品目コードの列の照合順序）と IB-110（`TEST_DATABASE` を渡した worktree の `bin/ci`）は M49 で実装した。M49 で作者に確かめることを OI-197（`judgment`）に、実装で見つけたことを IB-117・IB-118 に、実装レビューの違和感を IB-119・IB-120 に積んだ。作者の判断の受け口（`decisions.md`）に、M49 への判断は書かれていなかった。

## M47 複数の列で並べる

`m47-multi-sort`（base は `main`、PR #87）。M49 の `m49-collations` の先端 `e89ba05` から切った。M49（#86）は着手の後に main にマージされたので、M47 の差分は `e89ba05..` である。

Codex も Claude も Go だった。どちらの系統も、`e89ba05..5a8bbc8` の diff を `5a8bbc8` の版で読んだ。Codex は手元の DB への接続を実行の環境に拒まれ、rspec・E2E・CI は証跡の記録を前提にし、`Page` のカーソルの後ろの条件を式を評価する代わりのオブジェクトで 516 とおりの境目について確かめ、`list.ts` の純関数を壊して落ちることを確かめた。Claude は `factory_ops_m47_review_test` で完了条件の spec と `purchase_orders_spec.rb` を流し（1674 examples, 0 failures）、副問い合わせ・空を含む合計・状況を組み合わせた 3 とおりの 3 つの列の並びを 1 件ずつのページで最後までたどり、1 ページで読んだ並びと一致することを確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Medium 1） | 出していない（High が無かった） |
| Claude | Go（Medium 2、Low 3） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（R1） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘なし | 指摘（R2・R3） |
| 参照の維持 | 指摘（R1） | 指摘（R4・R5） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex・Claude | R1：証跡の「計画との違い」が計画の作るもの 4 の「操作」「表示」を直したと書くが、計画の節は直っていない（OI-198 の形、Shift を押した Enter、番号の幅のセルの空け方）。公開 API の `order_by:` の配列と、上限の example を発注の一覧で確かめることも計画の節に無い | 計画の節を直す文の置き換えの手順が、後ろの置き換えで止まって前の置き換えを書き出さずに終わっていた。作るもの 1 に公開 API の配列と `Page::Sort.of` の確かめを、作るもの 2 に上限ちょうどと上限 + 1 を発注の一覧で確かめることを、作るもの 4 の「操作」に OI-198 の形と Shift を押した Enter を、「表示」に番号の幅のセルの空け方と変種の URL を書いた。`git grep` で「立つ見込み」「同じ列は 昇順 → 降順 → 既定の並び）。Shift」が計画に残らないことを確かめた | この節を載せた commit |
| Medium | Claude | R2：`nextSort` の上限ちょうど（並びが 2 つのときに Shift で 3 つ目を足せること）の example が無い | `list.test.ts` の 3 つの並びの example に、2 つから 3 つ目を足す期待を足した。`current.length < MAX_SORTS - 1` に壊すと落ちることを確かめた | 同上 |
| Low | Claude | R3：かんばんの example は引当済の列しか見ず、ほかの未完了の列から `thenBy` を外しても落ちない | `dashboard_spec.rb` に、`SupplierKanban.graphql` の 7 つの列の `orderBy` と `thenBy` を文書から読んで確かめる example を足した。受注済の列だけから `thenBy` を外すと落ちることを確かめた | 同上 |
| Low | Claude | R4：`graphql-schema.md` が上限を `Page::MAX_SORTS` の 1 か所と書くが、画面にも `list.ts` の `MAX_SORTS` がある | 文書を 2 か所の形に直し、`spec/graphql/sort_arguments_spec.rb` に 2 つが同じ値であることを確かめる example を足した。画面の値を 4 に壊すと落ちることを確かめた | 同上 |
| Low | Claude | R5：`sortable-head.tsx` に `onKeyDown` を置かない理由が無く、IB-121 が Shift を押した Enter を挙げていない | `onClick` の前に理由のコメントを書き、IB-121 に Shift を押した Enter も Chromium でしか確かめていないことを足した | 同上 |

違和感は次のように扱った。

- Claude 1：`Page::Sort.of` に前の形（1 つの列のハッシュ）を渡すと `TypeError` で落ちる → 配列でない `order_by` を `ArgumentError`（`not a list`）にし、`page_spec.rb` に example を足した。確かめを外すと落ちることを確かめた
- Claude 2：品目と在庫の画面が `parseSort` を画面と変数の関数で 2 回呼ぶ → 同じ純関数を同じ値に 2 回呼ぶだけで、結果は食い違わないので扱わない
- Claude 3：IB-106（複数の列の効き目を画面で見せるか）は、見出しの操作と E2E で一部に答えた → サイクル末の台帳の棚卸しで IB-106 を読み直す材料として、ここに書く
- Claude 4：`graphql-schema.md` の SDL のブロックで、`salesOrders(...)` の行が型の外に単独で置かれていた → `type SupplierView { … }` の中に置いた
- Claude 5：2 つ目からの列の見出しのアクセシブル名が、見えない文字を含んで長くなる → 計画のとおり（ボタンの名前は変えず、列の見出しで順番と向きを伝える）なので扱わない

### 実装の記録

#### 計画との違い

- 公開 API（`Sales::SalesOrders.list` など 5 つ）の `order_by:` を、`{ field:, direction: }` の配列にした。`Page::Sort.of` が配列を受け取って `Sort` の配列を返し、`Page.of` の `sort:` も配列にしたからである。計画は `Page.of` の形だけを書き、公開 API の引数の形を書いていなかった。単体の spec が 1 つの列のハッシュを渡していたのを、`bin/ci` の 1 回目（`f29bd10`、3051 examples, 17 failures）で見つけ、`04df574` で配列に直した。計画の作るもの 1 に書いた（実装レビューの R1 で直した）。
- 引数の検証は、5 つのリゾルバが `include` する `Resolvers::SortArguments` に置いた。`sort_arguments <型>Order` が `orderBy` と `thenBy` の引数とリゾルバの検証を足す。`Page::Sort.of` も、列の重なりと 4 つ以上の列を引数の誤り（`ArgumentError`）にする。GraphQL の外から公開 API を呼ぶ入口（spec・シード）でも同じ上限を守るためで、上限は `Page::MAX_SORTS` の 1 か所にある。
- Shift を押さずに見出しを押したときの向きを、並びがその列 1 つのときだけ進め、並びが 2 つ以上なら並びにある列もその列 1 つの昇順にした。計画は並びが 2 つ以上のときの向きを決めていなかった。計画の作るもの 4 の「操作」を直し、OI-198（`judgment`）に積んだ。
- 番号の出る数値の列のセルは、矢印の幅に番号の幅を足して右に空ける（`components/ui/table.tsx` の `SORT_RANK_SLOT`、`components/columns.tsx` の `sortCell`）。番号を矢印に重ねて幅を取らない形にすると、受注一覧の最後の列（受注合計）の番号が表の右端からはみ出す。寸法の E2E の変種を `?sort=status,total_amount&dir=asc,desc` にし、2 つ目の列を数値の最後の列にして、そろえと番号の収まりを測る。`e2e/support/table-align.ts` に、番号が矢印の右にあり見出しのセルに収まる確かめを足した。計画の作るもの 4 の「表示」を直した。
- E2E の文字の選択の確かめを、`window.getSelection()` が空であることに加えて、document で受けた `mousedown` の `defaultPrevented` で確かめる形にした。Chromium はボタンの上の Shift を押したクリックで文字を選ばず、Shift を押した `mousedown` の既定の動きを止めるのを外しても、表の文字を押してから Shift を押して見出しを押しても、選ばれた文字は空のままだった（`e2e/list-pagination.spec.ts` で 2 回、静的な表で 1 回確かめた）。計画の作るもの 4 の「文字の選択」と完了条件を直し、Chromium でしか確かめられないことを IB-121 に積んだ。
- Shift を押した Enter で、クリックの `shiftKey` が Chromium で立つことを E2E で確かめたので、`onKeyDown` は置かなかった。計画の作るもの 4 の「操作」を直した。
- 計画の作るもの 5 の外で、`spec/matrix/graphql_matrix_spec.rb` に、`thenBy` を受け取るフィールドをスキーマから集め、どれも `thenBy` を渡す変種の行を持つことを確かめる example を足した。変種の行の規則を `guides/testing.md` に書くだけでは、一覧を足した人が行を足し忘れても何も落ちないからである。計画の作るもの 5 に足した。
- 計画の作るもの 2 の外で、`spec/requests/purchase_orders_spec.rb` に、`orderBy` と `thenBy` を合わせて 3 つの列を受け付け、4 つをトップレベルのエラーにする example を足した。品目の一覧は列が 2 つしかなく、上限ちょうどと上限 + 1 を確かめられないからである。計画の作るもの 2 に書いた（実装レビューの R1 で直した）。
- 前の形（「並べ替えの列は 1 つ」「`page_sort_value`」「同じ列は 昇順 → 降順 → 既定の並び」）を `git grep` し、`graphql-schema.md`「ページングと N+1」、計画の M39 の節（M47 で `thenBy` を足したと時点を書いた）、`sortable-head.tsx`・`list.ts` のコメントを直した。残るのは証跡（`docs/plans/`）と、作者の判断の行（OI-187）の内容の欄だけである。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：spec を足し、実装を変える前（`e89ba05` の作業ツリー）に流した。

- `bundle exec rspec spec/requests/catalog_spec.rb spec/requests/dashboard_spec.rb spec/requests/purchase_orders_spec.rb`（32 examples, 4 failures）
  - `catalog_spec.rb` の、名前の同じ品目を `thenBy` のコードの降順で並べる example：`expected: [{"code" => "N-2"}] got: nil`（`thenBy` を受け付けず、`data` が無い）
  - `catalog_spec.rb` の、`orderBy` を省いた `thenBy` と同じ `field` の重なりをエラーにする example：`expected: ["thenBy requires orderBy"] got: ["Field 'items' doesn't accept argument 'thenBy'", "Variable $thenBy is declared by anonymous query but not used"]`
  - `dashboard_spec.rb` の、かんばんの画面の問い合わせが希望納期の同じ受注を受注番号の昇順に並べる example：`expected: ["SO-K00001", "SO-K00002"] got: ["SO-K00002", "SO-K00001"]`
  - `purchase_orders_spec.rb` の、3 つの列を受け付け 4 つをエラーにする example：`expected: {"data" => {"buyer" => {"purchaseOrders" => {"totalCount" => 1}}}} got: {"errors" => [… "Field 'purchaseOrders' doesn't accept argument 'thenBy'" …]}`
- `frontend` で `npx vitest run lib/list.test.ts`（18 tests, 13 failed）。計画が挙げた Shift の example は `expected { field: 'ORDER_NO', direction: 'ASC' } to deeply equal [ { field: 'STATUS', …(1) }, …(1) ]`（いまの `nextSort` は Shift を受け取らず、列 1 つの並びに置き換える）。ほかの 12 件は、`parseSort` と `nextSort` が並びではなく 1 つの値を返す期待の不一致と、無い関数（`sortArgs`）の呼び出しで落ちた。`sortArgs` の example は読み込みの失敗でしか落ちていないので、下の壊して落ちる記録で RED に代える
- E2E：実装の後に、`frontend` の実装のファイルと単体のテストを `e89ba05` に戻し（E2E の spec と API は新しいまま）、`E2E_DATABASE=factory_ops_m47_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e -- e2e/list-pagination.spec.ts` を流した（1 failed, 4 passed）。受注一覧の Shift の example が、`expected ["status,customer_name", "asc,asc"]` に `received ["customer_name", "asc"]` で落ちた（いまの見出しは Shift を受け取らず、取引先の列 1 つの並びにする）

壊して落ちる記録：壊すファイルを一時ファイルの置き場に複製してから壊し、複製から戻した（`02e4561`〜`04df574` の作業ツリー）。戻した後に同じ spec を流し、すべて通った。

| 確かめる example | 壊したもの | 落ちたもの |
|---|---|---|
| `page_spec.rb` の、1 つ目の列の値が空の行がページの境目をまたぐ example | 前の列が同じことの比べ方を `IS NOT DISTINCT FROM` から `=`（`InfixOperation`。空どうしを同じとみなさない）にする | 3（この example と、M39 の列 1 つの ASC・DESC の 2 つ。値の無い行どうしの後ろが抜ける） |
| `page_spec.rb` の、向きの違う 2 つの列で 1 つ目の列の値が同じ行がページの境目をまたぐ example | 2 つ目からの列の「後」の比べ方の向きを入れ替える | 4（この example と、1 つ目の列が空の example、3 つの列の example、カーソルの拒否の example） |
| `page_spec.rb` の、2 つ目の列の向きだけを変えたカーソルを拒む example | カーソルの読み取りで、2 つ目からの列の向きを比べない | 1（この example） |
| `page_spec.rb` の、列が 1 つのカーソルを名前・向き・値・id の形で読み書きする example | カーソルの配列の先頭に id を置く | 5（この example と、複数の列のカーソルの形、金額のカーソルの 2 つ、形の誤ったカーソルの拒否） |
| `page_spec.rb` の、`Page::Sort.of` が 3 つまでを受け付け 4 つと重なりを拒む example | `Page::Sort.of` の列の数と重なりの確かめを外す | 1（この example） |
| `catalog_spec.rb` の、同じ `field` を 2 回書いた並べ替えをトップレベルのエラーにする example | `Resolvers::SortArguments::Validator` から重なりの確かめを外す | 1（この example） |
| `catalog_spec.rb` の、`orderBy` を省いた `thenBy` をエラーにする example | 同じ検証で、`orderBy` が無いときに通す | 1（この example） |
| `purchase_orders_spec.rb` の、4 つの列をエラーにする example | 同じ検証から列の数の確かめを外す | 1（この example） |
| `dashboard_spec.rb` の、かんばんの未完了の列の example | `SupplierKanban.graphql` の未完了の 4 つの列から `thenBy` を外す | 1（この example。`got: ["SO-K00002", "SO-K00001"]`） |
| `graphql_matrix_spec.rb` の、`thenBy` を受け取るフィールドが変種の行を持つ example | `"SupplierView.stocks#thenBy"` の行を消す | 1（この example。`got: ["SupplierView.stocks"]`） |
| `list.test.ts` の、長さの違う `sort` と `dir` を既定の並びにする example | `parseSort` から並びの長さの比べ方を外す | 1（この example） |
| `list.test.ts` の、同じ列を 2 回含む `sort` を既定の並びにする example | `parseSort` から同じ列の重なりの確かめを外す | 1（この example） |
| `list.test.ts` の、並びが 3 つのときに Shift で列を足さない example | `nextSort` が 3 つのときも Shift で列を足す | 1（この example） |
| E2E の受注一覧の Shift の example の並び | `sortArgs` が `thenBy` を渡さない | 1（この example。状況の同じ行に、取引先の名前が昇順に並ぶ組が残る） |
| E2E の受注一覧の Shift の example の `mousedown` | Shift を押した `mousedown` の既定の動きを止めない | 1（この example。`defaultPrevented` が `false`） |
| 同上の対照（Shift を押さないクリック） | すべての `mousedown` の既定の動きを止める | 1（この example。Shift を押さないクリックの `defaultPrevented` が `true`） |
| E2E の寸法の受注一覧の 2 つの列の並びの変種 | 番号の出る数値の列のセルに、番号の幅を空けない（`SORT_ICON_SLOT` のまま） | 1（この変種。受注合計の各行で、セルの右端が見出しの文字の右端と 12px ずれる） |

`sortArgs` の単体の example は、上の E2E と同じ壊し方（`thenBy` を渡さない）で `npx vitest run lib/list.test.ts lib/supplier-master-lists.test.ts` を流し、`list.test.ts` の `sortArgs` の example と、`supplier-master-lists.test.ts` の品目の一覧の変数の example の 2 件が落ちることを確かめた。

### 確かめたこと

#### E2E

`frontend` で `E2E_DATABASE=factory_ops_m47_e2e PLAYWRIGHT_CHANNEL=chrome npm run test:e2e` を Node 22.23.3 で流した（E2E の DB を、ほかの担当の `factory_ops_e2e` と分けた）。`04df574` の作業ツリーで 70 passed・26 skipped だった。受注一覧の Shift の example は、Shift を押した Enter で 2 つ目の列が並びから外れることまで通った。

#### 手元で流したもの

`04df574` の作業ツリーで、Ruby 3.4.11・PostgreSQL 18.6・Node 22.23.3 で流した。

```sh
TEST_DATABASE=factory_ops_m47_test bin/ci   # すべての工程が通った。rspec は 3051 examples, 0 failures
TEST_DATABASE=factory_ops_m47_test bundle exec rspec packs/platform/spec/models/page_spec.rb spec/requests/catalog_spec.rb spec/requests/dashboard_spec.rb spec/matrix spec/graphql/query_budget_spec.rb spec/graphql/query_complexity_spec.rb   # 1664 examples, 0 failures
bin/check-schema-compat   # bin/ci の工程で通った（破壊的な変更 0 件）
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 145 tests passed
bin/check-open-items --due M47   # 通った
bin/check-commit-refs            # 通った
```

`bin/ci` の 1 回目（`f29bd10`）は、公開 API の単体の spec が `order_by:` に 1 つの列のハッシュを渡したまま 17 件落ち（3051 examples, 17 failures）、`04df574` で直した。分岐の網羅率の警告は 0 件だった。

実装の記録を載せた `87214b0` の PR の CI はすべて通った（`test` 6 分 8 秒、`e2e` 3 分 29 秒、`images` 1 分 57 秒。`publish` は PR なので skip。[実行](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38511905424)）。

実装レビューの直しの後も、`232eee7` の作業ツリーで `TEST_DATABASE=factory_ops_m47_test bin/ci` を流し、すべての工程が通った（rspec は 3053 examples, 0 failures、分岐の網羅率の警告は 0 件）。`frontend` の `codegen:check`・`lint`・`typecheck`・`test:unit`（145 tests passed）と、`bin/check-open-items --due M47`・`bin/check-commit-refs` も通った。`27f9d2f` の PR の CI はすべて通った（`test` 5 分 59 秒、`e2e` 3 分 27 秒。[実行](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38514548779)）。

### 残件の処理

引当先が M47 の行は、着手の前と PR の前に台帳を読んだ。OI-187（`decided`、見出しで 2 つ目からの列を足す作者の判断）は作るもの 4 で、OI-195（`judgment`、Shift の操作の細部）は計画のとおりに反映した。実装で決めたことを OI-198（`judgment`）に、Chromium でしか確かめられないことを IB-121 に積んだ。作者の判断の受け口（`decisions.md`）に、M47 への判断は書かれていなかった。
