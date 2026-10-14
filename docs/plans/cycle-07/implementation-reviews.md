# サイクル 7 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M48 CI で依存の木を確かめ、イメージの組み立てを PR のたびに流す

`m48-ci-deps-check`（base は `main`、PR #84）。サイクル 07 の計画の `cycle-07-decisions` の先端 `8ad4320` から切った。計画の PR #83 が未マージの間は、その commit も PR の差分に見える。M48 の差分は `8ad4320..` である。

### 実装の記録

#### 計画との違い

- `publish` の `skipped` の守り（作るもの 3）は、計画の `!contains(needs.*.result, 'skipped')` の項をジョブの段に戻す形ではなく、`if:` を `github.event_name == 'push'` だけにし、状態の関数を書かずに GitHub が足す暗黙の `success()` に任せる形にした（`38864fb`）。`success()` は `needs` のどれかが落ちた・取り消された・skip されたときに偽になるので、`!cancelled()` と `failure`・`cancelled`・`skipped` の 3 つの項を並べた式と同じ守りになる。M42 で `!cancelled()` を要したのは、push で skip される `image_inputs` が `success()` を偽にしたからで、`image_inputs` を外せばその理由が無くなる。確かめ方は下の「`publish` の条件」にある。計画の M48 の作るもの 3 と `guides/config.md`「CI の工程」を直し、OI-184 の結果の欄に書いた。
- `ci_checks_spec.rb` の `needs` の example に、ジョブの段の `continue-on-error` を持つジョブが無いことの確かめを足した。壊し方の型の試行（作るもの 4）で、`images` にジョブの段の `continue-on-error: true` を足しても何も落ちず、そのジョブが落ちても `needs` の結果は `success` になり、`publish` がそのジョブの成功を待たなくなるからである。`guides/config.md`「CI の工程」に書いた。
- 計画の「文書に残すこと」の外で、`README.md`「画面」の検査のコマンドに `npm ls --all > /dev/null` を足した。CI の `frontend` のジョブと同じ検査を手元で流す手順だからである。
- 「`image_inputs`」は、`git grep` で `implementation-plan.md`（M42・M48 の節と前提の表）と `docs/plans/` のほかに 0 件である。`adr/009`「見直す条件」は、戻すときの形を名前を使わずに「M42 で作り M48 で外した、PR が変えたファイルで判定するジョブ」と書いた。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：`spec/platform/ci_checks_spec.rb` に `npm ls --all` の example を足し、`needs` と `if:` の example の期待を外した後の形に直し、ワークフローを変える前（`8ad4320` の作業ツリー）に流した（8 examples, 3 failures）。

- `npm ls --all` の example：`expected ["npm run codegen:check", "npm run lint", "npm run typecheck", "npm run test:unit"] to include "npm ls --all"`
- `publish` の `needs` の example：`expected: [] got: ["image_inputs"]`
- ジョブの段の `if:` の example：`expected: ["publish"] got: ["image_inputs", "images", "publish"]`

`continue-on-error` の確かめは GREEN の後に足したので、下の壊して落ちる記録で RED に代える。

ワークフローを 1 か所ずつ壊し、`bundle exec rspec spec/platform/ci_checks_spec.rb` を流して、ワークフローの複製から戻した（`38864fb` の版で。8 examples）。壊し方の型は IB-17 の試行の分類で、「消す・外す」のほかの型を、足すか直した example のそれぞれに 1 つ以上置いた。

| 確かめる example | 壊し方の型 | 壊したもの | 落ちたもの |
|---|---|---|---|
| `npm ls --all` | 消す | `npm ls --all` のステップを消す | 1（この example） |
| 〃 | 順を入れ替える | ステップを `npm ci` の前に動かす | 1（同上） |
| 〃 | 外す | 引数から `--all` を外す | 1（同上） |
| 〃 | 値を替える | 引数を `--depth=0` に替える | 1（同上） |
| 〃 | 条件を足す | ステップに `if: false` を足す | 1（同上） |
| 〃 | 要素を足す | ステップに `continue-on-error: true` を足す | 1（同上） |
| 〃 | 書き込み先を替える | ステップの `working-directory` を根（`.`）に替える | 1（同上） |
| `publish` の `needs` | 消す | `needs` から `manifests` を消す | 1（この example） |
| 〃 | 値を替える | `needs` の `manifests` を `images` に替える（重複） | 1（同上） |
| 〃 | 要素を足す | `needs` に無いジョブ `audit` を足す | 1（同上） |
| 〃（`continue-on-error`） | 要素を足す | `images` にジョブの段の `continue-on-error: true` を足す | 1（同上。`got: ["images"]`）。足す前の example では 0 で落ちなかった |
| ジョブの段の `if:` | 条件を足す | `images` に `if: github.event_name == 'pull_request'` を足す | 1（この example） |
| 〃 | 条件を足す | `e2e` に `if: always()` を足す | 1（同上） |
| 〃 | 消す | `publish` の `if:` を消す | 1（同上） |

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

### 残件の処理

引当先が M48 の行は、着手の前と PR の前に台帳を読んだ。どちらの時点でも無かった。OI-184（作者の確認で「M48 で簡単にできるかを確かめる」）の結果の欄に、M48 で戻した形と 2 つの実行の URL を書いた。IB-104・IB-113 は M48 で実装し、IB-17 の試行の標本は上の壊して落ちる記録である。IB-17 の効いたとする基準の後半（実装レビューの観点 4 で「壊しても落ちない」指摘が 2 系統とも 0 件）は、実装レビューの後にこの節に書く。
