# サイクル 6 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M42 CI のランナーの版を固定し、公開の配置のイメージを arm64 で組み立てる

`m42-ci-publish`（base は `main`、PR #74）。`cycle-06-plan` の先端 `4a14ee9` から切った。PR #73（`cycle-06-plan`）は作業中に main にマージされたので、M42 の差分は `4a14ee9..` で、PR の差分と同じである。

レビューの判定と指摘は、レビューを受けた後にここへ書く。

### 実装の記録

#### 計画との違い

- `publish` の `if:` から、計画の `!contains(needs.*.result, 'skipped')` の項を外した（OI-184）。M42 のブランチへの push で、ほかのジョブがすべて成功しても `publish` が skip され、ジョブの段の `if:` では `needs` の先で skip された `image_inputs` がこの項に見えたからである。確かめ方と、外したことで変わることは OI-184 にある。計画の M42 の作るもの 3 と `guides/config.md`「CI の工程」を直し、ワークフローの `publish` の直前のコメントに理由を書いた。
- `ci_checks_spec.rb` の `runs-on` の example は、`-arm` を持つジョブが `images` と `publish` のちょうど 2 つであることを確かめる。計画は「`images` と `publish` が `-arm` を持つこと」と書くが、`manifests` は amd64 の kubeconform を取るので、ほかのジョブが arm64 に移っても落とすことにした。作るもの 1 のジョブの振り分けのとおりである。
- `publish` の組み立ては、`images` と同じ `scope` のキャッシュを読むだけにし、キャッシュに書かない（`cache-to` を持たない）。キャッシュを書くのは `images` だけである。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：`spec/platform/ci_checks_spec.rb` に 3 つの example を足し、ワークフローを変える前に流した（7 examples, 3 failures）。

- `runs-on` の example：`expected: {} got: {"e2e" => "ubuntu-latest", "frontend" => "ubuntu-latest", "image_inputs" => "ubuntu-latest", "images" => "ubuntu-latest", "lint" => "ubuntu-latest", "scan_ruby" => "ubuntu-latest", "test" => "ubuntu-latest"}`
- push と `packages: write` の example：`expected: ["publish"] got: ["images"]`
- `publish` の `needs` の example：`expected: [] got: ["scan_ruby", "lint", "test", "frontend", "e2e", "images"]`

ワークフローを 1 か所ずつ壊し、`bundle exec rspec spec/platform/ci_checks_spec.rb` を流して、ワークフローの複製から戻した（`aa66ecd` の版で）。

| 壊したもの | 落ちたもの |
|---|---|
| `publish` の `needs` から `manifests` を外す・`test` を外す | それぞれ 1（`needs` の example） |
| ワークフローの最上位に `packages: write` を足す | 1（push と権限の example） |
| `images` の組み立てのステップに `push: true` を足す | 1（同上） |
| `publish` から `packages: write` を外す | 1（同上） |
| `e2e` を `ubuntu-latest` に戻す | 1（`runs-on` の example） |
| `images` を `ubuntu-24.04` にする・`manifests` を `ubuntu-24.04-arm` にする | それぞれ 1（同上） |

`publish` の `if:` の式と、ログインと push のステップの `if:` は、spec で守らない（`../../guides/config.md`「CI の工程」の、YAML の式を文字列で照らさない方針）。下の「確かめたこと」の、ブランチへの push の 3 回で確かめた。

### 確かめたこと

#### `images` の時間

PR #74 の CI で測った。ワークフローの時間は、実行が始まってから終わるまでで、どの回も `test` のジョブが最も長かった。

| 回 | commit | `images` | 内訳 | ワークフロー |
|---|---|---|---|---|
| 最初の PR の CI（main への push が書いたキャッシュが当たった） | `aa66ecd` | 1 分 0 秒 | Rails のイメージ 33 秒・本番の環境の起動 3 秒・画面のイメージ 7 秒 | 6 分 2 秒 |
| キャッシュが空（`scope` を `api-m42-cold`・`frontend-m42-cold` に替えた一時の commit） | `57ae9d1` | 4 分 10 秒 | Rails のイメージ 1 分 59 秒・起動 2 秒・画面のイメージ 1 分 50 秒 | 5 分 36 秒 |
| キャッシュが効く（`scope` を戻した commit の 1 回目） | `3616b83` | 1 分 1 秒 | Rails のイメージ 35 秒・起動 2 秒・画面のイメージ 8 秒 | 3 分 50 秒 |
| 同じ commit の 2 回目（`images` だけを流し直した） | `3616b83` | 59 秒 | Rails のイメージ 33 秒・起動 2 秒・画面のイメージ 8 秒 | — |

実行の URL：[`aa66ecd`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38352228976)、[`57ae9d1`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38352793422)、[`3616b83`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38353341535)（1 回目と 2 回目は同じ実行の試行 1 と 2）。

キャッシュが空でも、`images` は PR の CI の予算（10 分）の内に終わり、`test` のジョブ（5 分台）より短い。QEMU の上では、キャッシュが空のときに 25〜35 分かかった（`../cycle-05/implementation-reviews.md`「M41 Raspberry Pi の k3s への配置」）。`adr/009`「見直す条件」と `guides/config.md`「CI の工程」の引用を、この値で書き直した。`image_inputs` の条件を外すかは計画の範囲外で、この値で改善の探索が判定する（IB-93）。

#### `publish` の条件（M42 のブランチへの push）

`publish` は main への push でしか流れないので、一時の commit でワークフローの `on.push.branches` に `m42-ci-publish` を足し、ブランチへの push で確かめた。どの push でも、`image_inputs` は skip され、`images` は流れた。push は force push を挟まずに続けた。

| push | commit | ほかのジョブ | `publish` |
|---|---|---|---|
| 契機を足した（計画の `if:`） | `4233c87` | すべて成功 | skip。計画と違うので、下の調べに進んだ |
| 調べのジョブ（`run` の式に状態の関数を書いた） | `024a4d2` | — | ワークフローの書式の誤りで、ジョブが 1 つも始まらなかった（`run` の式では `cancelled()` を使えない） |
| 調べのジョブ（同じ `needs` で、`toJSON(needs)` を出し、同じ式をステップの `if:` に置いた） | `406904d` | すべて成功 | skip。調べのジョブでは、`needs` は 7 つとも `success` で、ステップの段の同じ式は真になり、そのステップが流れた |
| 項ごとの調べのジョブ | `b0c4038` | すべて成功 | skip。ジョブの段で、`!contains(needs.*.result, 'skipped')` を持つジョブは、`needs` が `images` だけでも skip され、`scan_ruby` だけなら流れた。`failure` の項と `github.event_name` の項だけのジョブは流れた |
| 1 回目：`skipped` の項を外し、調べのジョブを外した | `70a3f97` | すべて成功 | 流れて成功（53 秒、組み立て直しは Rails 30 秒・画面 7 秒）。ログインと push のステップは skip |
| 2 回目：`spec/platform/env_helpers_spec.rb` に落ちる example を 1 つ足した | `6d4aa26` | `test` だけが落ちた（2862 examples, 1 failure、足した example）。ほかは成功 | skip |
| 3 回目：落ちる example を戻し、`if:` から `!cancelled()` を外した | `38ce094` | すべて成功 | skip。状態の関数が無いと、暗黙の `success()` で skip される |

実行の URL：[`4233c87`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38353844622)、[`024a4d2`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38354325407)、[`406904d`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38354404040)、[`b0c4038`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38355008965)、[1 回目 `70a3f97`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38355675428)、[2 回目 `6d4aa26`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38356302629)、[3 回目 `38ce094`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38356890950)。

3 回目で `publish` は skip されたので、`!cancelled()` が要ることを確かめた。`ff7a689` で一時の commit を戻し、`on.push.branches` を `[ main ]` だけにし、`publish` の `if:` に `!cancelled()` を戻した。`aa66ecd` からのワークフローの差分は、`skipped` の項を外したことと、その理由のコメントだけである。

M42 をマージした後の最初の main への push で、`publish` が走り、ログインと push のステップが実行されて 2 つのイメージが GHCR に置かれることは、取りまとめ役がサイクル 06 の振り返りで確かめる（計画の M42 の完了条件）。

#### 手元で流したもの

`ff7a689` に、この節と台帳と文書の直しを載せた作業ツリーで、Ruby 3.4.11・PostgreSQL 18 で流した。

```sh
bundle exec rspec spec/platform/ci_checks_spec.rb   # 7 examples, 0 failures
bin/ci                                              # すべての工程が通った。rspec は 2861 examples, 0 failures
bin/check-open-items --due M42                      # 通る
```

分岐の網羅率の警告は 0 件だった（M42 は Ruby のコードを変えていない）。

### 残件の処理

引当先が M42 の行は、着手の前と PR の前に台帳を読んだ。着手の前は 1 つも無かった。M42 で決めたことは OI-184 に judgment で積んだ。
