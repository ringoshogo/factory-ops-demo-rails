# サイクル 6 のマイルストーンの実装レビュー

マイルストーンの PR をマージする作者が、レビューの指摘がどう片付いたかを確かめるために読む。担当者は、PR の実装レビューを受けたら、そのマイルストーンの節に、各系統の判定と、指摘ごとの対応と、直した commit を書く。指摘を直さずに残すときは、残す理由を対応の列に書く。

レビューは 2 系統で行う。Codex は差分とリポジトリを読み、手元でコマンドを流して確かめる。Claude は差分を設計文書と突き合わせる。判定は Go（そのままマージしてよい）・Conditional Go（指摘を直せばマージしてよい）・No-Go のどれかである（`../../guides/dev-cycle.md`「判定の形」）。

## M42 CI のランナーの版を固定し、公開の配置のイメージを arm64 で組み立てる

`m42-ci-publish`（base は `main`、PR #74）。`cycle-06-plan` の先端 `4a14ee9` から切った。PR #73（`cycle-06-plan`）は作業中に main にマージされたので、M42 の差分は `4a14ee9..` で、PR の差分と同じである。

Codex も Claude も Go だった。どちらの系統も、`4a14ee9..0871a4f` の diff を `0871a4f` の版で読んだ。Claude は証跡の実行の URL のうち 5 つを `gh run view` で読み、表と一致することを確かめた。Codex は GitHub の実行を読めず、証跡と依頼に書いた実行結果を前提にし、spec をワークフローの壊し方を替えて手元で流した。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

2 系統の Medium は同じことを挙げた。`skipped` の項を外した後は、push で skip された `needs` のジョブが push を止めず、守りが文書の規則だけになっていた。ステップの段の守りと spec の両方で直した。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Medium 1・Low 2） | 出していない（High が無かった） |
| Claude | Go（Medium 1・Low 1） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（R2） |
| 正しさ | 指摘なし | 指摘（R1） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R2） | 指摘なし |
| 参照の維持 | 指摘（R3） | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Claude・Codex | Claude R1・Codex R2：`skipped` の項を外したので、push で skip された `needs` のジョブ（たとえば `images`）があっても `publish` が走り、本番の環境で起こしていないイメージを置く。守りは `config.md` の文だけで、`e2e` に PR だけの `if:` を足しても spec が通る | `publish` の最初のステップに `if: contains(needs.*.result, 'skipped')` で落とすステップを置いた（ステップの段では直接の `needs` だけが見える）。`ci_checks_spec.rb` に、ジョブの段の `if:` を持つジョブが `image_inputs`・`images`・`publish` だけであることを確かめる example を足した。ブランチへの push で、`images` を skip させるとこのステップで落ち、すべて成功なら skip されることを確かめた（下の「確かめたこと」）。OI-184・計画の作るもの 3・`config.md` を合わせた | `ba15a27`・`826f981` |
| Low | Claude・Codex | Claude R2・Codex R1：キャッシュが効く 2 回目は `images` だけを流し直したので、ワークフロー全体の時間が無い | 同じ commit の全ジョブを流し直し、全体の時間を表に足した（試行 3 は `e2e` が `next build` で落ちたので、試行 4 も流した） | — |
| Low | Codex | R3：OI-172 が、`images` がマニフェストを照らして同じイメージを push する前の形を書いている | OI-172 の内容に、CI の部分を M42 で替えたことと、いまの置き場（`guides/config.md`「CI の工程」）を書き足した | この節を載せた commit |

違和感は次のように扱った。

- Claude 1：計画レビューの「指摘の根拠を確かめた結果」の、`needs.*.result` は直接の `needs` の配列になるとした行が、OI-184 の観測と食い違って見える → OI-184 に、その行は文書どおりでステップの段の振る舞いに合い、ジョブの段の振る舞いは観測だけに頼ることと、調べ直す条件を書いた
- Claude 2：push の検出が `docker push` と `push: true` だけで、`docker buildx build --push` などを拾わない → IB-100
- Codex：なし

### 実装の記録

#### 計画との違い

- `publish` の `if:` から、計画の `!contains(needs.*.result, 'skipped')` の項を外した（OI-184）。M42 のブランチへの push で、ほかのジョブがすべて成功しても `publish` が skip され、ジョブの段の `if:` では `needs` の先で skip された `image_inputs` がこの項に見えたからである。確かめ方と、外したことで変わることは OI-184 にある。計画の M42 の作るもの 3 と `guides/config.md`「CI の工程」を直し、ワークフローの `publish` の直前のコメントに理由を書いた。
- `ci_checks_spec.rb` の `runs-on` の example は、`-arm` を持つジョブが `images` と `publish` のちょうど 2 つであることを確かめる。計画は「`images` と `publish` が `-arm` を持つこと」と書くが、`manifests` は amd64 の kubeconform を取るので、ほかのジョブが arm64 に移っても落とすことにした。作るもの 1 のジョブの振り分けのとおりである。
- `publish` の組み立ては、`images` と同じ `scope` のキャッシュを読むだけにし、キャッシュに書かない（`cache-to` を持たない）。キャッシュを書くのは `images` だけである。
- 外した `skipped` の項の守りを、`publish` の最初のステップと、ジョブの段の `if:` を持つジョブを限る spec に置いた（実装レビューの Medium、OI-184）。

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
| `e2e` に `if: github.event_name == 'pull_request'` を足す（`ba15a27` の前の作業ツリーで） | 1（ジョブの段の `if:` の example。`got: ["e2e", "image_inputs", "images", "publish"]`） |

ジョブの段の `if:` の example は、実装レビューの指摘で足し、書いた時点のワークフローでは通ったので、上の壊して落ちる記録で RED に代える。

`publish` の `if:` の式と、最初のステップ・ログイン・push のステップの `if:` は、spec で守らない（`../../guides/config.md`「CI の工程」の、YAML の式を文字列で照らさない方針）。下の「確かめたこと」の、ブランチへの push で確かめた。

### 確かめたこと

#### `images` の時間

PR #74 の CI で測った。ワークフローの時間は、実行が始まってから終わるまでで、どの回も `test` のジョブが最も長かった。

| 回 | commit | `images` | 内訳 | ワークフロー |
|---|---|---|---|---|
| 最初の PR の CI（main への push が書いたキャッシュが当たった） | `aa66ecd` | 1 分 0 秒 | Rails のイメージ 33 秒・本番の環境の起動 3 秒・画面のイメージ 7 秒 | 6 分 2 秒 |
| キャッシュが空（`scope` を `api-m42-cold`・`frontend-m42-cold` に替えた一時の commit） | `57ae9d1` | 4 分 10 秒 | Rails のイメージ 1 分 59 秒・起動 2 秒・画面のイメージ 1 分 50 秒 | 5 分 36 秒 |
| キャッシュが効く（`scope` を戻した commit の 1 回目） | `3616b83` | 1 分 1 秒 | Rails のイメージ 35 秒・起動 2 秒・画面のイメージ 8 秒 | 3 分 50 秒 |
| 同じ commit の 2 回目（`images` だけを流し直した） | `3616b83` | 59 秒 | Rails のイメージ 33 秒・起動 2 秒・画面のイメージ 8 秒 | — |
| 同じ commit の 3 回目（全ジョブを流し直した。`e2e` が落ちた） | `3616b83` | 1 分 27 秒 | — | 5 分 18 秒 |
| 同じ commit の 4 回目（全ジョブを流し直した） | `3616b83` | 1 分 3 秒 | Rails のイメージ 36 秒・起動 2 秒・画面のイメージ 9 秒 | 4 分 3 秒 |

実行の URL：[`aa66ecd`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38352228976)、[`57ae9d1`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38352793422)、[`3616b83`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38353341535)（1〜4 回目は同じ実行の試行 1〜4）。

3 回目の `e2e` は、`next build` が `next/font/google` を解決できずに落ちた（`Can't resolve '@vercel/turbopack-next/internal/font/google/font'`）。M42 は画面を変えておらず、同じ commit の 1 回目と 4 回目は通った。M42 のブランチの実行で、`826f981` までに `e2e` を流した 25 回のうち、落ちたのはこの 1 回である。`next/font/google` は組み立ての時に Google Fonts から取るので、取れなかったときの落ち方とみなし、IB-101 に積んだ。

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

実装レビューの指摘で `publish` の最初のステップを足した後（`ba15a27`）、もう一度契機に M42 のブランチを足して 2 回確かめた。

| push | commit | ほかのジョブ | `publish` |
|---|---|---|---|
| `images` の `if:` を push で skip される条件にした | `58d7c76` | `images` が skip、ほかは成功 | ジョブの段では走り、最初のステップで落ちた。組み立て・ログイン・push のステップは skip |
| `images` の `if:` を戻した | `9d0e6e9` | すべて成功 | 流れて成功（1 分 0 秒）。最初のステップ・ログイン・push のステップは skip |

実行の URL：[`58d7c76`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38359032386)、[`9d0e6e9`](https://github.com/ringoshogo/factory-ops-demo-rails/actions/runs/38359526842)。`826f981` で契機を戻し、`on.push.branches` は `[ main ]` だけになった。`ba15a27` からのワークフローの差分は無い。

M42 をマージした後の最初の main への push で、`publish` が走り、ログインと push のステップが実行されて 2 つのイメージが GHCR に置かれることは、取りまとめ役がサイクル 06 の振り返りで確かめる（計画の M42 の完了条件）。

#### 手元で流したもの

`ff7a689` に、この節と台帳と文書の直しを載せた作業ツリーで、Ruby 3.4.11・PostgreSQL 18 で流した。

```sh
bundle exec rspec spec/platform/ci_checks_spec.rb   # 7 examples, 0 failures（実装レビューの直しの後は 8 examples, 0 failures）
bin/ci                                              # すべての工程が通った。rspec は 2861 examples, 0 failures
bin/check-open-items --due M42                      # 通る
```

実装レビューの直しの後も、`826f981` にこの節と台帳の直しを載せた作業ツリーで `bin/ci` を流し、すべての工程が通った（rspec は 2862 examples, 0 failures）。分岐の網羅率の警告は、どちらの回も 0 件だった（M42 は Ruby のコードを変えていない）。

### 残件の処理

引当先が M42 の行は、着手の前と PR の前に台帳を読んだ。どちらの時点でも、OI-184 のほかには無かった。M42 で決めたことは OI-184 に judgment で積んだ。実装レビューの違和感は IB-100 に、CI で 1 回だけ起きた `next build` の落ち方は IB-101 に積んだ。

## M43 公開の配置の作り直しを、本番の環境でだけ動かす

`m43-reset-production-only`（base は `main`、PR #75）。M42 の先端 `4dc35fb` から切った。M42 の PR #74 が未マージなので、PR の差分には M42 も含まれる。M43 の差分は `4dc35fb..` である。

Codex も Claude も Go だった。どちらの系統も、`4dc35fb..8881593` の diff を `8881593` の版で読んだ。Claude は `spec/platform/demo_reset_spec.rb` を手元で流し、`DemoReset#run` を差し替える変異を読み込ませて検出力を確かめた。Codex はファイルを変えず、`git grep` で入口の条件の記述を数えた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Low 1） | 出していない（High が無かった） |
| Claude | Go（Low 1） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘なし | 指摘なし |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘なし | 指摘（R1） |
| 参照の維持 | 指摘（R1） | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Low | Claude | R1：本番の環境で `DEMO_WORLD_ENABLED` が無いか 1 でないときの example が、ロック（`PG.connect`）を見ていない。門の条件だけを `with_lock` のブロックの先頭へ動かす変異が、16 examples, 0 failures で通った | その example に、止まったときに `PG.connect` を呼ばないことと、対照で呼ぶことを足した。同じ変異で、その example が `expected: 0 times ... received: 1 time` で落ちることを確かめた（下の壊して落ちる記録の最後の行） | この節を載せた commit |
| Low | Codex | R1：`handoff.md` が、レビューの結果を証跡に書く前の版で「M42・M43 は実装レビューまで終え」と書いている | この節を載せた commit で、レビューの結果と `handoff.md` の PR の番号を同時に書いた | この節を載せた commit |

違和感は次のように扱った。

- Claude 1：`adr/009` 決定 3 と M41 の作るもの 3 の最後の段落が「DB を消す工程は `DEMO_WORLD_ENABLED` を渡した作り直しだけ」と書き、M43 で直した `data-model.md` と言い方がそろわない → どちらも公開の配置（本番の環境）の中のことを言う文で誤りではないので直さず、IB-102 に積んだ
- Claude 2：`handoff.md` の記述がレビューに先行している → Codex R1 と同じ。上の表のとおり直した
- Codex：なし

### 実装の記録

#### 計画との違い

- `Refused` の文言は、2 つの条件を 1 つの文（「本番の環境で DEMO_WORLD_ENABLED=1 を渡したときだけ動く」）にまとめ、どちらの条件で止まったかを分けなかった。どちらも、作者が本番の環境の作り直しの Job に変数を渡し直せば済む同じ対処になるからである。
- 「文書に残すこと」の `lib/demo_reset.rb` の冒頭のコメントのほかに、入口の条件を前の形（`DEMO_WORLD_ENABLED=1` だけ）で書いていた 2 か所を直した。`architecture/data-model.md`「監査ログ」の公開の配置の例外と、`implementation-plan.md` の M41 の作るもの 3 の手順 1 である。`adr/009` 決定 3・4 と `deploy/README.md` は、本番の環境の配置の振る舞いだけを書いており、変わらない。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：`spec/platform/demo_reset_spec.rb` の「入口」に、開発とテストの環境で `DEMO_WORLD_ENABLED=1` を渡しても止まることを確かめる example を足し、`lib/demo_reset.rb` を変える前に流した（16 examples, 1 failure）。いまの門は開発とテストで開くので、入口を通って所有ロールでロックを取り、ServiceAccount の場所が無いことで落ちた（IB-90 の、処理の順に頼った止まり方そのもの）。

```
expected DemoReset::Refused with message matching /本番の環境/, got #<KeyError: key not found: "KUBERNETES_SERVICE_HOST">
  # ./lib/demo_reset/kubernetes.rb:17:in 'DemoReset::Kubernetes.from_service_account'
  # ./lib/demo_reset.rb:41:in 'block in DemoReset#run'
  # ./lib/demo_reset.rb:65:in 'DemoReset#with_lock'
```

この example は、開発とテストの環境の両方で止まることと、`PG.connect`・`Kubernetes.from_service_account`・Kubernetes の API・DB のタスク・シード（`DemoWorld.build`）のどれも呼ばないことを確かめ、同じ準備で本番の環境に替えれば、ロックを取り、API・DB のタスク・シードを呼ぶことを対照にする。

実装を 1 か所ずつ壊し、`bundle exec rspec spec/platform/demo_reset_spec.rb` を流して、ファイルの複製から戻した。

| 壊したもの | 落ちたもの |
|---|---|
| 入口の条件から、本番の環境の条件（`Rails.env.production? &&`）だけを外す | 1（上の example。RED と同じ `KeyError`） |
| 入口の条件から、門（`Platform::DemoWorldGate.open?`）だけを外す | 1（「入口」の、本番の環境で `DEMO_WORLD_ENABLED` が無いか 1 でなければ止まる example） |
| spec の「作り直し」の準備から、本番の環境（`production!`）を外す | 11（「作り直し」のすべて） |
| spec の「作り直し」の準備から、`DEMO_WORLD_ENABLED=1` を外す | 11（同上） |
| 入口を本番の環境の条件だけにし、門の条件を `with_lock` のブロックの先頭（`from_service_account` の前）へ動かす（実装レビューの Claude R1 の直しの後） | 1（「入口」の、本番の環境で `DEMO_WORLD_ENABLED` が無いか 1 でなければ止まる example。`expect(PG).not_to have_received(:connect)` が `received: 1 time`） |

3・4 行目は、計画の作るもの 2 の準備が、どれも入口を通るために要ることを確かめた。最後の行は、門で止まるときもロックを取らないことを確かめた。

#### 手元で流したもの

`4dc35fb` に M43 の変更を載せた作業ツリーで、Ruby 3.4.11・PostgreSQL 18 で流した。

```sh
bundle exec rspec spec/platform/demo_reset_spec.rb   # 16 examples, 0 failures
bin/ci                                               # すべての工程が通った。rspec は 2863 examples, 0 failures
```

分岐の網羅率の警告は 0 件だった。実装レビューの直しの後も、この節と台帳の直しを載せた作業ツリーで `bin/ci` を流し、すべての工程が通った（rspec は 2863 examples, 0 failures、分岐の網羅率の警告 0 件）。

### 残件の処理

引当先が M43 の行は、着手の前に台帳を読んだ時点で無かった（`bin/check-open-items --due M43` が通る）。IB-90 は計画どおり `DemoReset#run` に条件を置き、`DemoWorldGate` の意味は変えていない。実装レビューの違和感は IB-102 に積んだ。

## M44 依存の更新を取り込み、Dependabot の更新をまとめる

`m44-dependency-updates`（base は `main`、PR #76）。M43 の先端 `56b529f` から切った。M42 の PR #74 と M43 の PR #75 が未マージなので、PR の差分には M42・M43 も含まれる。M44 の差分は `56b529f..` である。

Codex も Claude も Go だった。どちらの系統も、`56b529f..afdf731` の diff を `afdf731` の版で読んだ。Claude は `spec/platform/dependency_updates_spec.rb` と `npm ls --all` を手元で流し、`package-lock.json` の版と GitHub の Dependabot の文書を照らした。Codex は Rails を起こさずに commit のファイルを読んで spec の条件を評価する形で、組のまとまりへの変異を確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Medium 2・Low 1） | 出していない（High が無かった） |
| Claude | Go（Medium 1・Low 2） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（R1） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R2） | 指摘（R2・R3） |
| 参照の維持 | 指摘（R3） | 指摘なし |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex・Claude | R1：完了条件の「M44 の PR の CI で `frontend`・`e2e`・`images` が通る」が、証跡で確かめられていない。action の主版の上げは手元で確かめる手段が無い | PR #76 の `afdf731` の run（38366504749）で、`frontend`・`e2e`・`images` を含むすべてのジョブが通った（`publish` は PR では skip）ことを「手元で流したもの」の後に書いた。`actions/upload-artifact` は `e2e` が落ちたときにだけ動くので、この run では動いていない | この節を載せた commit |
| Medium | Codex | R2：組のまとまりの example が `patterns` と位置だけを見る。組のまとまりに `update-types: [minor, patch]` を足すか、`exclude-patterns` に `react-dom` を足しても 10 examples, 0 failures で通る | 組のまとまりが `update-types` を持たず、組の依存を `exclude-patterns` に持たないことを同じ example に足した。2 つの変異で落ちることを壊して落ちる記録に足した。`guides/config.md` と計画の作るもの 4 にも書いた | `7f92b56` |
| Low | Claude | R2：Codex R2 の前者と同じ | 同上 | `7f92b56` |
| Low | Claude | R3：`@types/node` の範囲は先頭の数だけで主版を読み、`>=22` のような範囲も通る | `@types/node` の範囲が 1 つの主版に収まる形（`^`・`~` か記号なし）であることを足した。`>=22` で落ちることを壊して落ちる記録に足した。計画の作るもの 3 と `guides/config.md` にも書いた | `7f92b56` |
| Low | Codex | R3：`guides/config.md` の Dependabot の段落が、外部の仕様（最初に当たったまとまりに入る、`update-types` を省くと主版も含む）に依存するのに原文を引いていない | GitHub の文書（Dependabot options reference の `groups` と `ignore`）へのリンクを足した | `7f92b56` |

違和感は次のように扱った。

- Claude 1：`ci.yml` の `actions/setup-node` の直前のコメントが `engines` の値（`^22.12`）を書き写していて、spec の外で古くなりうる → 値を外し、正本を指す形にした（`7f92b56`）
- Claude 2：IB-104 の「`npm ci` は peer の範囲の外を ERESOLVE で止めないことがあり」が、計画の完了条件の段落（組の依存の不一致は `npm ci` が止める）と、直接の依存の組と入れ子の依存の違いで読み分けにくい → IB-104 の言い方を、直接の依存の組と入れ子の依存に書き分けた（`7f92b56`）
- Claude 3：`groups` が `applies-to` を省き、セキュリティの更新はまとめずに 1 本ずつ開くことに `guides/config.md` が触れていない → IB-105 に積んだ
- Codex 1：CI が `npm ls --all` を流さない → IB-104 と同じで、新しくは積んでいない
- Codex 2：Codex の確かめは Rails を起こさない形で、通常の spec の実行ではない → 確かめ方の注記で、成果物への観察ではないので、ここに書くだけにした

### 実装の記録

#### 取り込んだ更新と、取り込まなかった更新

着手の時点（2026-10-13）で開いていた Dependabot の PR は、計画の表と同じ 13 本で、版も進んでいなかった。Dependabot の PR はマージも close もせず、同じ版をこのブランチで入れた。主版の上げと組の上げは commit を分け、各 commit で完了条件の 2 行目（`npm ci`・`npm ls --all`・`codegen:check`・`lint`・`typecheck`・`test:unit`）を Node 22.23.3 で流した。

| commit | 更新 | 結果 |
|---|---|---|
| `0020b17` | `actions/checkout` 7・`actions/cache` 6・`actions/upload-artifact` 7・`actions/setup-node` 7（#15・#16・#63・#64） | 取り込んだ。ワークフローの同じ action の `uses:` をすべて同じ主版にした。PR の CI で確かめる |
| `1812763` | `react`・`react-dom` 19.3.0（#62・#69） | 取り込んだ。画面の検査と E2E が通った |
| `b930131` | `graphql` 17.0.2（#61） | 取り込んだ。`codegen:check` が生成物の変化なしで通った |
| — | `eslint` 10.12.0（#70） | 取り込まなかった（下） |
| `5264b18` | `cn` 0.4.0（#68） | 取り込んだ。画面の検査と E2E が通った |
| `25379aa` | `@base-ui/react` 1.9.0・`lucide-react` 1.54.0（#67・#71） | 取り込んだ。どちらも小版の上げで、1 つの commit にまとめた。画面の検査と E2E が通った |

`eslint` 10.12.0 は、`npm install --save-dev eslint@10.12.0` が通り、`npm run lint` も通ったが、`npm ls --all` が失敗で終わった。`eslint-config-next` 16.4.0 が入れる `eslint-plugin-import`（peer は `^2 || … || ^9`）・`eslint-plugin-jsx-a11y`（`^3 || … || ^9`）・`eslint-plugin-react`（`^3 || … || ^9.7`）が `eslint` 10 を範囲に含まない。#70 の CI は `frontend`・`e2e`・`images` を含めてすべて通っていたが、CI は `npm ls --all` を流さない。計画の作るもの 1 のとおり、commit にせず外して、計画の表の取り込まない行に移した（`882f474`）。

```
npm error code ELSPROBLEMS
npm error invalid: eslint@10.12.0 .../frontend/node_modules/eslint
```

`lucide-react` は着手の時点で 1.56.0 が出ていたが、#71 の版（1.54.0）で入れた。PR の版が進んでいなかったからである。

#### 計画との違い

- `eslint` 10 を取り込まない行に移した（上）。#70 を `ignore` にせず開いたままにすることは計画に無く、OI-185 に積んだ。上げる時機を IB-103 に、CI が `npm ls --all` を流さないことを IB-104 に積んだ
- 「文書に残すこと」のほかに、`ci.yml` の `actions/setup-node` の直前のコメント（`engines` を「22.12 以上」と書いていた）を、`engines` の新しい形に合わせた

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：`spec/platform/dependency_updates_spec.rb` を書き、`dependabot.yml` と `engines` を変える前に流した（`56b529f` の作業ツリー、10 examples, 7 failures）。落ちたのは、`groups`（`expected [...] to all include "groups"`）、`engines` の形（`expected ">=22.12" to match /\A\^\d+\.\d+\z/`）、小版と修正版のまとまりの `update-types`（`got: {"bundler" => [], "npm" => []}`）、組のまとまりの位置（`expected: not nil`）、0 系の依存の除外（`got: ["class-variance-authority", "cn"]`）、github-actions のまとまり（`expected {} to include {"patterns" => ["*"]}`）、`@types/node` の `ignore`（`expected [] to include (a hash including ...)`）の 7 つである。Node の主版をそろえる 3 つ（`setup-node`・`NODE_VERSION`・`@types/node`）は、いまの版がそろっているので通った。これらは下の壊して落ちる記録で RED に代える。

GREEN の後に 1 か所ずつ壊し、`bundle exec rspec spec/platform/dependency_updates_spec.rb` を流して、ファイルの複製から戻した。

| 壊したもの | 落ちたもの |
|---|---|
| `frontend/Dockerfile` の `NODE_VERSION` を 24.11.0 にする | 1（`NODE_VERSION` の example） |
| 2 つ目の `actions/setup-node` の `node-version` を 24 にする | 1（`setup-node` の example） |
| 2 つ目の `actions/setup-node` の `node-version` を `node-version-file` に替える | 1（同上） |
| 1 つ目の `actions/setup-node` の `node-version` を文字列の `"24.x"` にする | 1（同上）。`"22.x"` にすると通る |
| `@types/node` の範囲を `^26.6.5` にする | 1（`@types/node` の example） |
| bundler と npm の小版と修正版のまとまりの `update-types` に `major` を足す | 1（`update-types` の example） |
| npm の組のまとまりを、小版と修正版のまとまりの後ろへ動かす | 1（組のまとまりの位置の example） |
| `cn` を `exclude-patterns` から外す | 1（0 系の依存の example） |
| 組のまとまりに `update-types: [ minor, patch ]` を足す（実装レビューの Codex R2 の直しの後） | 1（組のまとまりの example） |
| 組のまとまりに `exclude-patterns: [ react-dom ]` を足す（同上） | 1（同上） |
| `@types/node` の範囲を `>=22` にする（実装レビューの Claude R3 の直しの後） | 1（`@types/node` の example） |

`npm ls --all` が組の依存の不一致を捕まえることは、`npm install --legacy-peer-deps --save-exact react-dom@19.3.0` で `react` を 19.2.8 のままにした木で確かめた。`npm ls --all` が `npm error code ELSPROBLEMS` と `npm error invalid: react@19.2.8 ...`（`"^19.3.0" from node_modules/react-dom`）で、終了コード 1 で終わった。`package.json` と `package-lock.json` を戻して `npm ci` を流し直した後は、0 で終わった。

#### 手元で流したもの

`882f474` の作業ツリーで、Ruby 3.4.11・PostgreSQL 18・Node 22.23.3 で流した。

```sh
bundle exec rspec spec/platform/dependency_updates_spec.rb spec/platform/ci_checks_spec.rb   # 18 examples, 0 failures
cd frontend && npm ci && npm ls --all > /dev/null && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 通った。test:unit は 136 tests
cd frontend && PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # 65 passed、25 skipped（E2E_SCREENSHOTS が無いときに飛ばすスクリーンショット）
bin/ci   # すべての工程が通った。rspec は 2873 examples, 0 failures
bin/check-open-items --due M44
bin/check-commit-refs
```

分岐の網羅率の警告は 0 件だった。

PR #76 の CI は、`afdf731` の run（38366504749）で、`frontend`・`e2e`・`images`・`test`・`lint`・`scan_ruby`・`manifests`・`image_inputs` が通り、`publish` は PR なので skip された。上げた 4 つの action のうち、`actions/checkout`・`actions/cache`（`lint` の RuboCop のキャッシュ）・`actions/setup-node` はこの run で動いた。`actions/upload-artifact` は `e2e` が落ちたときにだけ動くステップで、この run では動いていない。

実装レビューの直し（`7f92b56`）の後に、`bundle exec rspec spec/platform/dependency_updates_spec.rb spec/platform/ci_checks_spec.rb` と `bin/ci` を流し直した。spec は 18 examples, 0 failures、`bin/ci` はすべての工程が通り、rspec は 2873 examples, 0 failures、分岐の網羅率の警告は 0 件だった。

### 残件の処理

引当先が M44 の行は、着手の前に台帳を読んだ時点で無かった。OI-163（画面の Node を 22 系にした判断）は、`engines` を `^22.12` にして主版を 1 つに決め、spec で 4 か所をそろえたので、内容は変わらない。IB-99 は計画どおり `typescript` 7 の PR を開いたままにした。実装で積んだのは OI-185・IB-103・IB-104 で、実装レビューの違和感は IB-105 に積んだ。

## M45 受注・発注・出荷依頼を、取引先の名前と合計と状況で並べる

`m45-list-sort`（base は `main`）。計画の PR #78（`cycle-06-decisions`）の先端 `2daa00b` から切った。#78 が未マージなので、PR の差分には計画の commit も含まれる。M45 の差分は `2daa00b..` である。

Codex も Claude も Go だった。どちらの系統も、`2daa00b..8bf31e6` の diff を `8bf31e6` の版で読んだ。実装者が 2 系統へ同じ依頼を渡した。Claude は spec を流さず、`git grep` で `field: :status` と `SORT_ORDER` を引いて検出力を見た。Codex は spec を流さず、`Page#decode` をメモリ上で呼んでカーソルの受け付けと拒否を確かめ、`SORT_ORDER` の順位をメモリ上で入れ替えて比較が変わらないことを確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Go（Medium 1・Low 1） | 出していない（High が無かった） |
| Claude | Go（Medium 1・Low 2） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R2） | 指摘（R3） |
| 正しさ | 指摘なし | 指摘なし |
| 境界と規約 | 指摘なし | 指摘なし（文書の言い回しは R2） |
| テストの検出力 | 指摘（R1） | 指摘（R1） |
| 参照の維持 | 指摘（R2） | 指摘（R2・R3） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex・Claude | R1：状況で並べる順（`SORT_ORDER`）の大半の順を、どの spec も確かめていない。状況のモジュールの単体は `ALL` と同じ集まりであることだけを見、公開 API の spec は状況の一部しか並べない。受注の一部引当と引当済、発注の入荷予定と検収済、出荷依頼の出荷停止中と出荷済を入れ替えても落ちない | 3 つの状況のモジュールの単体に、全状況の行を 1 件ずつ作って `STATUS` で並べ、`graphql-schema.md`「状況の enum」の表から書き写した順（`DESC` はその逆）に並ぶことを確かめる example を足した。レビューが挙げた入れ替えで落ちることを、壊して落ちる記録に足した | `0fb56c1` |
| Low | Codex・Claude | R2：`graphql-schema.md`「1 回のリクエストがたどる道」3 が、テナントの名前の副問い合わせも「scope を掛けた後」の例に含めている。`adr/010` 決定 2 の見出しも同じ | 3 の括弧からテナントの名前を外し、所有テナントの無い表の値は scope を掛けずに返す列を絞る、という文を分けて足した。決定 2 の見出しに「所有テナントの無い表は、返す列を絞って」を足した | `0fb56c1` |
| Low | Codex・Claude | R2（Codex）・R3（Claude）：計画の作るもの 4 がカーソルの合計を「整数に戻し」と書いたまま。`data-model.md`「状態は保存せず、時刻列から導出する」の、状況の式を読む使い方に並べ替えが無い | 作るもの 4 を「`numeric` で比べるために `BigDecimal` に戻し」に直し、理由を添えた。`data-model.md` に、並べ替えも同じ式の値を読み、順は優先順でなく業務の進み順であることを足した。「整数に戻し」は `git grep` で計画・設計文書・コードに 0 件 | `0fb56c1` |

違和感は次のように扱った。

- Codex 1・Claude 1：明細が 0 件の受注と発注は、合計が空になり「照合待ち」「確定待ち」と出る。入口からは作れない → IB-108 に積んだ
- Codex 2：別の DB の worktree で `logging_spec.rb` が落ちたのは既存の依存で、M45 はテストの基盤を変えていない → `TEST_DATABASE` を渡した worktree で `bin/ci` を流せないこととして IB-110 に積んだ
- Claude 2：E2E の受注一覧の example が、世界の受注が 1 ページに収まり得意先が 2 社であることに依る → IB-109 に積んだ
- Claude 3：`page.rb` の `BigDecimal` の理由が、Active Record の既定値の原文を引いていない → activerecord 8.1 の `ActiveRecord.raise_int_wider_than_64bit` と `check_int_in_range` を引いた（`0fb56c1`）
- Claude 4：M45 の差分は 788 行の追加で、IB-107 の「分けた後も大きい」に当たる → `2daa00b..0fb56c1` で 58 ファイル・845 行の追加と 132 行の削除、生成物（`schema.graphql`・`frontend/lib/graphql/generated.ts`）と `docs/` を除くと 49 ファイル・636 行の追加と 104 行の削除だった。IB-107 の判定の材料として、ここに書くだけにした

### 実装の記録

#### 計画との違い

- 取引先の名前は、計画の作るもの 1 の「外部結合し、名前の列で並べる」ではなく、副問い合わせから伝票の相手のテナント ID の行の名前を行ごとに 1 つ引くスカラーの副問い合わせ（`SqlSubquery#lookup`）で並べた。`Page` は並べ替えの式 1 つを受け取り、ページと件数を同じ relation から引く。外部結合では名前で並べるときだけ relation に結合を足すことになり、結ぶ条件を書き誤ると伝票の行と件数が黙って増える。スカラーの副問い合わせでは、2 行以上が当たると SQL のエラーになる。OI-191 に積み、計画の作るもの 1・6、`adr/010` 決定 2、`architecture/graphql-schema.md`「ページングと N+1」をこの形に書いた。作るもの 6 の行列の行は、結ぶ条件を外すと SQL のエラーで落ちる（下の壊して落ちる記録）
- カーソルの合計の値は、計画の「整数に戻す」ではなく `BigDecimal` に戻した。Active Record は `bigint` を超える `Integer` を比べる値にすると `IntegerOutOf64BitRange` を投げ（`ActiveRecord.raise_int_wider_than_64bit`）、`bigint` を超える和の次のページが 500 になるからである。受け付ける形（`\A\d{1,31}\z`）は計画のとおりである
- 発注一覧に「発注合計」の列と、取引先・状況の並べ替えの矢印を足すと、1024px で表がパネルから 19px はみ出し、`e2e/layout.spec.ts` の `/buyer/purchase-orders` が落ちた。列の最小幅を決めていたのは、折り返さない希望納期のセル（「10月16日 あと2日」）だった。`DueDate` を、表のセルの中でだけ日付と文言の間の空白で折り返せるようにした（`frontend/components/date-text.tsx`）。日付と文言の中では折り返さず、かんばんのカードでは 1 行のままにする
- 画面の合計の表示を 1 つの関数（`totalAmountText`）にしたので、受注一覧と発注一覧の合計のセルも、受注詳細とかんばんのカードと同じく「円」を付けて出す。受注詳細の明細ごとの金額（単価 × 数量）は、単価のある明細だけで計算し、0 として足す形を消した
- 状況の位置を返す式（`array_position`）は、3 つの状況のモジュールで同じ形なので、`Page::Sort.rank` に 1 つで置いた

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）は、計画が名指しした次の 3 つである。どれも実装の前に流した。

`packs/sales/spec/public/sales/sales_orders_spec.rb` の、照合待ちの明細を含む受注の `to_h` が `total_amount: nil` を持つ example（`2daa00b` の作業ツリー、platform の変更だけを入れた状態）。

```
expected {cancellation_review_pending: false, customer_tenant_id: "...", due_... "SO-F00001", owner_tenant_id: "...", status: :awaiting_part_match} to include {total_amount: nil}
```

`spec/requests/purchase_orders_spec.rb` の、`orderBy: { field: SUPPLIER_NAME, direction: ASC }` で発注の一覧を読む example。列を足す前は引数の検証のエラーで `nodes` が無い。最初の版は `nodes` に `map` を呼んで `NoMethodError` で落ちたので、RED に数えず、`nodes` を期待と比べる形に書き直して流し直した。

```
expected: [{"orderNo" => "PO-000002", "supplier" => {"name" => "あおば製作所"}}, {"orderNo" => "PO-000001", ...}, {"orderNo" => "PO-000003", ...}]
     got: nil
```

`frontend/e2e/list-pagination.spec.ts` の、受注一覧を取引先の名前と受注合計で並べ、照合待ちの受注が一覧・詳細・かんばんのカードのどれでも「照合待ち」と出る example（API の変更だけを入れ、画面を変える前）。最初の版は `getByRole("button", { name: "取引先" })` が絞り込みの「取引先」のボタンに当たり、URL の期待の不一致で落ちた。見出しの中のボタンに絞って流し直した。

```
Error: expect(locator).toBeVisible() failed
Locator: getByRole('columnheader', { name: '取引先' }).getByRole('button')
Error: element(s) not found
```

ほかの spec は実装の後に書いた。GREEN の後に 1 か所ずつ壊し、ファイルの複製から戻した。

| 壊したもの | 流した spec | 落ちたもの |
|---|---|---|
| 受注の合計の式の「単価の無い明細があれば空」を `false` にする | `sales_orders_spec.rb` | 2（`total_amount: nil` の example と、合計で並べて照合待ちが末尾に来る example） |
| 受注の合計の式の `numeric` への変換を外す | `sales_orders_spec.rb` | 2（`bigint` を超える和の example が SQL のエラーで、合計で並べる example も同じ） |
| 発注の合計の式の「単価の写しの無い明細があれば空」を `false` にする | `purchase_orders_spec.rb`（購買の単体） | 1（合計で並べる example）。最初は単価の写しの無い明細だけの発注で確かめていて、和がもともと空になるので 0 failures だった。写しの有る明細と無い明細を混ぜた発注に直した |
| 発注の合計の式の `numeric` への変換を外す | `spec/requests/purchase_orders_spec.rb` | 1（`bigint` を超える `totalAmount` の example） |
| 発注の値への写しで合計を `to_f` にする | `spec/requests/purchase_orders_spec.rb` | 1（同上。10 進の文字列が期待と一致しない） |
| 受注の値への写しで合計を `to_f` にする | `sales_orders_spec.rb` | 1（`bigint` を超える和を整数で持つ example） |
| カーソルの合計を整数の文字列にせずに書く | `page_spec.rb`・`sales_orders_spec.rb` | 2（`bigint` を超える和をカーソルで往復させる 2 つの example） |
| カーソルを読むときの桁の確かめを外す | `page_spec.rb` | 1（31 桁を超える値・負の値・小数のカーソルを拒む example） |
| 受注の `SORT_ORDER` から品番照合待ちを外す | 受注の状況の単体・`sales_orders_spec.rb` | 2（`ALL` と同じ集まりの example と、状況で並べる example） |
| 発注の `SORT_ORDER` から受注側で確認中を外す | 発注の状況の単体 | 1（`ALL` と同じ集まりの example） |
| 出荷依頼の `SORT_ORDER` から出荷停止中を外す | 出荷依頼の状況の単体 | 1（同上） |
| 発注の `SORT_ORDER` の受注済を先頭へ動かす | `purchase_orders_spec.rb`（購買の単体） | 1（状況で並べる example） |
| 出荷依頼の `SORT_ORDER` の出荷指示済を先頭へ動かす | `shipment_requests_spec.rb` | 1（状況で並べる example） |
| `Page::Sort.rank` の一覧を逆にする | `page_spec.rb` | 1（位置で並べる example） |
| 名前の副問い合わせに取引用コードを足す | `directory_spec.rb` | 1（列が ID と名前だけの example） |
| `tenant_names_sql` の操作者の確かめを外す | `directory_spec.rb` | 1（操作者でなければ引数の誤りにする example） |
| `SqlSubquery#lookup` の結ぶ条件を外す | `directory_spec.rb` | 1（行ごとに名前を 1 つ引く example） |
| 同上 | `spec/matrix/graphql_matrix_spec.rb -e orderByName` | 30（3 つの `#orderByName` の行の、全ペルソナの admin と member） |
| 受注・発注・出荷依頼の名前の副問い合わせを、相手のテナント ID でなく所有テナントの ID で引く | 3 つの公開 API の単体と `spec/requests/purchase_orders_spec.rb` | 受注 1・発注 2・出荷依頼 1（名前で並べる example） |
| 画面の `totalAmountText` で、空の合計を 0 円にする | `frontend/lib/format.test.ts` | 1（空の合計の example） |
| 受注の `SORT_ORDER` の一部引当と引当済を入れ替える（実装レビューの R1 の直しの後） | 受注の状況の単体 | 1（全状況を状況で並べる example） |
| 受注の `SORT_ORDER` の検収済と取消済を入れ替える（同上） | 同上 | 1（同上） |
| 受注の `SORT_ORDER` から最後の取消済を外す（同上） | 同上 | 2（同上と、`ALL` と同じ集まりの example。位置の無い状況は `DESC` でも最後に残るので、逆順の期待と食い違う） |
| 発注の `SORT_ORDER` の入荷予定と検収済を入れ替える（同上） | 発注の状況の単体 | 1（同上） |
| 発注の `SORT_ORDER` の取消済みと受注側により取消を入れ替える（同上） | 同上 | 1（同上） |
| 出荷依頼の `SORT_ORDER` の出荷停止中と出荷済を入れ替える（同上） | 出荷依頼の状況の単体 | 1（同上） |

`DueDate` を表のセルの中で折り返せるようにする前は、上の「計画との違い」のとおり `e2e/layout.spec.ts` の `/buyer/purchase-orders` が落ちた（`表の幅がパネルの中に収まる (表 707.25 / パネル 688)`）。直した後は通った。

#### 手元で流したもの

`8831090` の作業ツリーで、Ruby 3.4.11・PostgreSQL 18・Node 22.23.3 で流した。

```sh
bundle exec rspec packs/platform/spec/models/page_spec.rb packs/partnerships/spec/public/partnerships/directory_spec.rb   # 0 failures
bundle exec rspec packs/sales/spec/public/sales/sales_orders_spec.rb packs/sales/spec/models/sales/sales_order_status_spec.rb packs/purchasing/spec/public/purchasing/purchase_orders_spec.rb packs/purchasing/spec/models/purchasing/purchase_order_status_spec.rb packs/fulfillment/spec/public/fulfillment/shipment_requests_spec.rb packs/fulfillment/spec/models/fulfillment/shipment_request_status_spec.rb   # 0 failures
bundle exec rspec spec/matrix spec/requests/purchase_orders_spec.rb spec/graphql/query_budget_spec.rb spec/graphql/query_complexity_spec.rb   # 0 failures
bin/check-schema-compat   # 破壊的な変更 0 件
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 通った。test:unit は 138 tests
cd frontend && PLAYWRIGHT_CHANNEL=chrome npm run test:e2e   # 66 passed、25 skipped（E2E_SCREENSHOTS が無いときに飛ばすスクリーンショット）
bin/ci   # すべての工程が通った。rspec は 2920 examples, 0 failures
bin/check-open-items --due M45
bin/check-commit-refs
```

実装レビューの直し（`0fb56c1`）の後に、完了条件の rspec の 3 行・`bin/check-schema-compat`・`bin/check-open-items --due M45`・`bin/check-commit-refs` と `bin/ci` を流し直した。rspec の 3 行は 19・38・1546 examples でどれも 0 failures、`bin/ci` はすべての工程が通り、rspec は 2923 examples, 0 failures、分岐の網羅率の警告は 0 件だった。直しは画面を変えていないので、画面の検査と E2E は流し直していない。

分岐の網羅率の警告は 0 件だった。`bin/ci` は、はじめ `TEST_DATABASE` を渡して流し、`spec/platform/logging_spec.rb` の 1 件が `log/events.log` が無いことで落ちた。この example は既定の DB のプロセスが書いた `log/events.log` を読むので、別の DB に向けた worktree の初めての実行では落ちる。ほかに rspec を流しているプロセスが無いことを確かめてから、`TEST_DATABASE` を渡さずに流し直して通った。

### 残件の処理

着手の前に台帳を読み、引当先が M45 の行は OI-186・OI-188・OI-190（どれも `judgment`）だった。OI-188 は判断のとおり、発注の合計にも受注と同じ規則を当て、発注一覧に「発注合計」の列を足した。OI-186・OI-190 は判断のとおり、問いに無かった列を足さず、名前を DB の照合順序のまま並べた。どれも作者の確認を待つ `judgment` のままにした。OI-179（作者の判断）は、合計の式と `totalAmount` と画面の 1 つの関数で反映した。実装で決めたことを OI-191 に積んだ。

## M46 在庫を、品目のコードと名前で並べ、検索する

`m46-stock-item-sort`（base は `main`）。M45 のブランチ `m45-list-sort` の先端 `46aa4ed` から切った。計画の PR #78 と M45 の PR #79 が未マージなので、PR の差分にはそれらの commit も含まれる。M46 の差分は `46aa4ed..` である。

Codex は No-Go、Claude は Go だった。どちらの系統も、`46aa4ed..c75775b` の diff を `c75775b` の版で読んだ。実装者が 2 系統へ同じ依頼を渡した。Claude は spec を流さず、`git show` と `git grep` で読み、DB の照合順序を `compose.yaml` と IB-77 の記述から判断した。Codex は DB への接続を実行の環境に拒まれ、spec の補助をメモリ上で呼んで検出力を確かめた。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。両系統が同じ問題（作り直しと取り込みの品目のロックの順の食い違い）を挙げ、Codex は High、Claude は Medium にした。High があるので、重大度から表に照らして No-Go とし、直した `1c2a94b` を Codex の読み直しに出した。読み直しは、前の 3 つの指摘がどれも解消し、新しい指摘が無く、Go だった。Claude は Go だったので、読み直しに出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | No-Go（High 1・Medium 2） | `1c2a94b` で Go（R1〜R3 が解消、新しい指摘なし） |
| Claude | Go（Medium 1・Low 1） | 出していない（High が無かった） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R1） | 指摘（R1） |
| 正しさ | 指摘（R1） | 指摘（R1） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R2・R3） | 指摘（R1・R2） |
| 参照の維持 | 指摘（R1） | 指摘（R1） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| High（Codex）・Medium（Claude） | Codex・Claude | R1：`bulk_upsert` は Ruby の `sort_by`（バイトの順）で品目をロックし、`rebuild_item_labels` は DB の照合順序（`en_US.utf8`）の `ORDER BY code` で `FOR SHARE` を取る。`B-1` と `a-1` のように 2 つの順が逆になる品目コードで、取り込みと作り直しが行き詰まりうる。計画の作るもの 3 の「行き詰まらない」とコメントの「同じ品目コードの順」が成り立たない | 作り直しを `items.code COLLATE "C"` で並べ、バイトの順にそろえた。`item_labels_rebuild_lock_spec.rb` に、`a-1` を保存が持つ間に作り直しを始め、作り直しが `B-1` を先に取ることを、`B-1` の保存が作り直しを待つことで確かめる example を足した。計画の作るもの 3、`adr/011` 決定 1、コメントにロックの順と理由を書いた | `1c2a94b` |
| Medium | Codex | R2：競合テストの `read.pop` に期限が無く、`put` の包みを外すか作り直しが `put` の前に失敗すると、待ち続けて後始末に届かない | `ConcurrencyHelpers::WAIT_SECONDS` の期限を付け、期限を過ぎたら例外にした。包みを外すと、その example が期限で落ち、後の example は通ることを確かめた | `1c2a94b` |
| Medium | Codex | R3：在庫のパッケージの一括の書き込みの検査が、ファイル・囲むメソッド・呼ぶメソッドしか比べず、`ItemLabels.put` の `upsert_all` を `Stock.upsert_all` に替えても通る | 呼び出しの連なりの先頭の定数を書き込み先として比べるようにし、拾い方を確かめる example を足した | `1c2a94b` |
| Low | Claude | R2：作り直しのタスクの合計の行と `Counts#+` を確かめる spec が無い | `item_labels_spec.rb` に `Counts#+` の単体を足した。合計の行は、テストの DB にほかの spec が残したテナントの数も含むので、一致の spec では確かめない | `1c2a94b` |

違和感は次のように扱った。

- Claude 1：`StockFilterType`・`ItemFilterType` の説明が上限の値を文字列で持つ → 説明を `Keyword::MAX_LENGTH` から書くようにした（`1c2a94b`）。`schema.graphql` は変わらない
- Claude 2：在庫の検索の E2E が、世界の品目名と初期在庫に依る → IB-111 に積んだ
- Claude 3・Codex 1：差分の大きさ → `46aa4ed..c75775b` で 42 ファイル・997 行の追加と 60 行の削除。IB-107 の判定の材料として、ここに書くだけにした
- Claude 4：写しの無い在庫が一覧に出ないことは、在庫の行を作る経路が品目を経ることに依る → `adjustStock` は `Sales::Catalog.item` で品目を引いて見えない品目を `NOT_FOUND` にし、在庫の取り込みは品目コードから品目 ID を引くので、どの入口も品目のある在庫しか作らない。`adr/011` の見直す条件に、品目を経ない在庫の経路を書いてあるので、台帳には積んでいない

### 実装の記録

#### 計画との違い

- 作り直しのタスク（`read_models:rebuild`）は、`sales:backfill_item_prices` と違い、数が 0 のテナントの行も出す。一致の spec が、世界のテナントごとに 0 であることをタスクの出力から読むからである。テストの DB には、ほかの spec が残したテナントもあるので、spec は世界のテナントの行だけを読む
- `put` の戻り値は、足した数と書き直した数を持つ値（`Inventory::ItemLabels::Counts`）にした。タスクがテナントの数を足し合わせるので、足し算を持たせた
- 競合テスト `item_labels_rebuild_lock_spec.rb` は、`spec/support/concurrency.rb` の `in_thread`・`blocked_on_lock?` に加えて、作り直しのスレッドだけを品目を読んだ後、写しを書く前で止めるため、`Inventory::ItemLabels.put` を `and_wrap_original` で包んだ。作り直しを `hold_open` で開いたままにすると、作り直しが書いた写しの行ロックで保存が待つので、`FOR SHARE` を外しても保存が作り直しの後に写しを書き、落ちない
- 入口の行列の在庫の変種の行は `"SupplierView.stocks#keyword"` にした。いまの `"SupplierView.stocks#filter"`（有効在庫で並べ、安全在庫で絞る）を残し、品目名で並べて `keyword` で絞る行を足した
- E2E は、画面の問い合わせの変数（`filter.keyword`）をブラウザから見られないので、URL の `q` と、当たる在庫の行と件数を確かめる。URL の値を `filter.keyword` に写すことは、`frontend/lib/supplier-master-lists.test.ts` が確かめる
- `spec/db/lock_sites_spec.rb` の表に `Sales::Catalog.rebuild_item_labels` を足し、`Sales::Catalog.save` を、競合テストを持たない理由から `item_labels_rebuild_lock_spec.rb` に替えた。保存の行ロックが、作り直しを待たせる側になったからである。`packs/inventory/spec/models/inventory/stock_spec.rb` の一括の書き込みの検査に、在庫の行ではなく写しを書く `ItemLabels.put` の `upsert_all` を足した
- 写しを読む受注とルートの spec は、写しのモデルが在庫のパッケージの外に出ない（packwerk の `enforce_privacy`）ので、SQL で読む
- 公開の配置で作り直しを待たずに写しを埋める手順を、`deploy/README.md` に `kubectl exec` で `bin/rails read_models:rebuild` を流す形で書いた

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）は、計画が名指しした次の 2 つである。どちらも実装の前に流した。

`spec/requests/inventory_spec.rb` の、`filter: { keyword: "六角" }` で在庫の一覧を読む example（`46aa4ed` の作業ツリー）。`keyword` を足す前は引数の検証のエラーで `stocks` が無い。同じ example の対照（絞らなければ 3 件とも返る）は通った。

```
Failure/Error: expect(stocks(filter: { keyword: "六角" })).to eq([ %w[B-1 N-2], 2 ])

  expected: [["B-1", "N-2"], 2]
       got: nil
```

`frontend/e2e/list-pagination.spec.ts` の、在庫の画面で品目名の一部を検索する example（API の変更だけを入れ、画面を変える前）。API の `StockOrderField` に値を足すと、在庫の画面の `sortColumns` が型検査で落ちて `next build` が通らないので、見出しの文字に `ITEM_CODE`・`ITEM_NAME` を足すことだけをした。最初の版は検索の欄の `fill` が時間切れで落ちたので、欄が見えることを先に確かめる形に書き直して流し直した。

```
Error: expect(locator).toBeVisible() failed
Locator: getByRole('searchbox', { name: '検索' })
Error: element(s) not found
```

ほかの spec は実装の後に書いた。GREEN の後に 1 か所ずつ壊し、ファイルの複製から戻した。

| 壊したもの | 流した spec | 落ちたもの |
|---|---|---|
| `Sales::Catalog.bulk_upsert` から `Inventory::ItemLabels.put` の呼び出しを外す | `read_model_copies_spec.rb`・`catalog_bulk_upsert_spec.rb` | 4（一致の spec の 3 つ。世界の取り込みが写しを書かないので、世界を作った後の作り直しから 0 でない。取り込みの単体の写しの example） |
| `Sales::Catalog.save` から `put` の呼び出しを外す | `read_model_copies_spec.rb`・`catalog_spec.rb` | 4（一致の spec の 3 つと、保存の写しの example） |
| `put` の一意索引と `ON CONFLICT` の対象を品目 ID だけにする（テストの DB の索引を所有ロールで張り替えて流し、元に戻した） | `item_labels_spec.rb` | 2（他社の名義で同じ品目 ID の写しがあるときの `put` の 2 つ。開かないときも開いたときも RLS の例外） |
| 在庫の一覧で写しを結ぶ条件から所有テナントを外す | `item_labels_spec.rb`・`spec/matrix/graphql_matrix_spec.rb` | 1（`item_labels_spec.rb` の一覧の example だけ。入口の行列の 600 を超える example は落ちない） |
| `rebuild_item_labels` が品目を読む条件から所有テナントを外す | `catalog_spec.rb` | 1（RLS を開いたときの作り直しの example） |
| `rebuild_item_labels` の `FOR SHARE` を外す | `item_labels_rebuild_lock_spec.rb` | 1（写しが「古い名前」のまま残る） |
| 在庫の `keyword` で `Keyword` を通さずに LIKE を組む | `stocks_spec.rb` | 2（`%` と `_` の example と、全角の空白を除く example） |
| `put` の `IS DISTINCT FROM` の条件を外す（値の同じ写しも書き直す） | `item_labels_spec.rb`・`read_model_copies_spec.rb`・`catalog_spec.rb` | 5（`put` の数の example、一致の spec の 3 つ、作り直しの数の example） |
| `StockFilter` の `keyword` の長さの検証を外す | `spec/requests/inventory_spec.rb` | 1（100 文字ちょうどと 101 文字の example） |
| `Keyword::MAX_LENGTH` を 99 にする | `spec/requests/inventory_spec.rb`・`spec/requests/catalog_spec.rb` | 2（在庫と品目の 100 文字ちょうどの example） |
| `Keyword` の `sanitize_sql_like` を外す | `keyword_spec.rb`・`catalog_spec.rb`・`stocks_spec.rb` | 3（3 つの `%` と `_` の example） |
| `Keyword` の前後の空白の除き方を外す | `keyword_spec.rb` | 1 |
| `Keyword` の LIKE を大文字と小文字を区別する形にする | `keyword_spec.rb` | 1 |
| 在庫の `ITEM_NAME` の列を写しのコードにする | `stocks_spec.rb`・`spec/requests/inventory_spec.rb` | 2（品目名で並べる 2 つの example） |
| 画面の `stockListVariables` で `keyword` を送らない | `frontend/lib/supplier-master-lists.test.ts` | 1 |

実装レビューの直し（`1c2a94b`）の後に、次も壊して戻した。

| 壊したもの | 流した spec | 落ちたもの |
|---|---|---|
| 作り直しの `COLLATE "C"` を外す（DB の照合順序の `ORDER BY code` に戻す） | `item_labels_rebuild_lock_spec.rb` | 1（作り直しのロックの順の example。`B-1` の保存が作り直しを待たない） |
| 競合テストの `put` の包みで止めない | 同上 | 1（読み終わりの待ちが期限で例外になる。後の example は通った） |
| `ItemLabels.put` の書き込み先を `Stock` にする | `packs/inventory/spec/models/inventory/stock_spec.rb` | 1（一括の書き込みの検査） |

写しを結ぶ条件から所有テナントを外しても入口の行列が落ちないのは、計画の作るもの 7 のとおりで、品目 ID が UUIDv7 で他社の品目と重ならないからである。`item_labels_spec.rb` の一覧の example が、他社の名義で自社の在庫の品目 ID を指す写しを factory で作って捕まえる。

#### 手元で流したもの

`45d7161` で、Ruby 3.4.11・PostgreSQL 18・Node 22.23.3 で流した。

```sh
bundle exec rspec packs/platform/spec/models/keyword_spec.rb packs/sales/spec/public/sales/catalog_spec.rb packs/sales/spec/public/sales/catalog_bulk_upsert_spec.rb packs/inventory/spec/public/inventory/stocks_spec.rb packs/inventory/spec/public/inventory/item_labels_spec.rb   # 42 examples, 0 failures
bundle exec rspec spec/scenarios/read_model_copies_spec.rb packs/sales/spec/concurrency/sales/item_labels_rebuild_lock_spec.rb spec/matrix spec/requests/inventory_spec.rb spec/requests/catalog_spec.rb spec/graphql/query_budget_spec.rb   # 1562 examples, 0 failures
bin/check-schema-compat   # 落とす変更は無い
cd frontend && npm run codegen:check && npm run lint && npm run typecheck && npm run test:unit   # 通った。test:unit は 139 tests
bin/ci   # すべての工程が通った。rspec は 2977 examples, 0 failures
bin/check-open-items --due M46
bin/check-commit-refs
```

E2E（`cd frontend && PLAYWRIGHT_CHANNEL=chrome npm run test:e2e`）は、画面と E2E の変更を入れた作業ツリーで流し、67 passed、25 skipped（`E2E_SCREENSHOTS` が無いときに飛ばすスクリーンショット）だった。その後の変更は spec と文書だけで、画面は変えていない。

実装レビューの直し（`1c2a94b`）の後に、完了条件の rspec の 2 行・`bin/check-open-items --due M46`・`bin/check-commit-refs` と `bin/ci` を流し直した。rspec の 2 行は 43・1563 examples でどちらも 0 failures、`bin/ci` はすべての工程が通り、rspec は 2980 examples, 0 failures、分岐の網羅率の警告は 0 件だった。直しは画面を変えていないので、画面の検査と E2E は流し直していない。

分岐の網羅率の警告は 0 件だった。`bin/ci` は既定の DB で流した。はじめの `bin/ci` は、`spec/db/lock_sites_spec.rb` と在庫の一括の書き込みの検査（上の「計画との違い」）、packwerk（受注とルートの spec が写しのモデルを参照した）、`bin/check-structure`（`db/structure.sql` が未 commit だった）で落ち、直して commit した後に通った。

### 残件の処理

着手の前に台帳を読み、引当先が M46 の行は OI-189（`decided`。作者の判断で、品目の保存と取り込みが同じトランザクションで在庫の公開 API を呼んで写す）だった。判断のとおり、`Sales::Catalog.save`・`bulk_upsert` が `Inventory::ItemLabels.put` を呼ぶ形で作った。OI-190（名前を DB の照合順序のまま並べる、`judgment`）は、品目の名前も同じく照合順序のまま並べた。

## M41 の残り：公開の配置のプローブの時間切れを明示する

`m41-probe-timeouts`（base は `main`、PR #81）。M46 の先端 `5439b97` から切った。#78〜#80 が未マージなので、PR の差分には M44〜M46 の後の commit も含まれる。M41 の残りの差分は `5439b97..` である。M41 の作者の実機の手順（作るもの 9 の手順 1〜6）は作者が流すので、この PR では流していない。結果が書かれるまで M41 は閉じず、公開しない（`implementation-plan.md` M41「作者が実機で確かめること」）。

Codex も Claude も Conditional Go だった。どちらの系統も、`5439b97..f421a87` の diff を `f421a87` の版で読んだ。Codex はファイルを変えず、新しい example の本体をメモリの中で変えた YAML に当てて検出力を確かめた。Claude は `deploy_manifests_spec.rb` を手元で流し、マニフェストの複製を壊して戻した。Claude のサブエージェントは最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ。Codex は一時の失敗を起こさず、出し直していない。High 以上が無かったので、読み直しには出していない。

| 系統 | 判定 | 読み直し |
|---|---|---|
| Codex | Conditional Go（Medium 2・Low 1） | 出していない（High が無かった） |
| Claude | Conditional Go（Medium 2・Low 2） | 出していない（同上） |

| 観点 | Codex | Claude |
|---|---|---|
| 計画への準拠と範囲 | 指摘（R2） | 指摘（R1） |
| 正しさ | 指摘なし | 指摘（R2） |
| 境界と規約 | 指摘なし | 指摘なし |
| テストの検出力 | 指摘（R1） | 指摘（R4） |
| 参照の維持 | 指摘（R3） | 指摘（R3） |

| 重さ | 系統 | 指摘 | 対応 | commit |
|---|---|---|---|---|
| Medium | Codex・Claude | Codex R2・Claude R1：RED と壊して落ちる記録を証跡に書かないまま、レビューに出した（`guides/dev-cycle.md`「実装レビュー」） | 規則から外れた。この節の「実装の記録」に、直す前の RED と、直しの後の版で壊して落ちる記録を書いた。直しの後の版は High が無いので読み直しに出していない | この節を載せた commit |
| Medium | Claude | R2：`postgres` のプローブの `pg_isready` は自分でも既定の 3 秒で接続を諦め、kubelet の 5 秒を待たずに落ちる。手元の PostgreSQL 18 の `pg_isready --help` も `-t ... (default: 3)` と書く | 2 つのプローブに `-t 4` を渡し、kubelet の時間切れより少し短く待たせ、理由をコメントに書いた。計画のプローブの直しにも書いた | `315155b` |
| Medium | Codex | R1：新しい example は、すべてを `timeoutSeconds: 1` に戻しても、`web` の startupProbe を消しても通る | example が、プローブの組（`web` の 3 つ、`frontend` と `postgres` の 2 つずつ）を計画から書いた一覧と比べ、時間切れが整数で 1 秒より長いことと、`pg_isready` の `-t` がその内であることを確かめるようにした。値を 5 に固定しなかったのは、作者の手順 4 で値を直すたびに spec を直さずに済ませ、守るものを「既定の 1 秒より長く明示する」に絞るためである | `315155b` |
| Low | Claude | R4：同じ（`timeoutSeconds: 1` でも通る） | Codex R1 と同じ直し | `315155b` |
| Low | Claude | R3：`handoff.md` の「決まっていないこと」に OI-181 が残る | 消した。`git grep OI-181` で、計画・`handoff.md` に作者を待つとした記述が残らないことを確かめた | `315155b` |
| Low | Codex | R3：コメントが依拠する外部の既定値（時間切れの 1 秒）の原文の参照が無い | 計画のプローブの直しに、Kubernetes の Probe の API が `timeoutSeconds` の既定を 1 秒とすること（`periodSeconds` は 10 秒、`failureThreshold` は 3 回）を書いた。ADR は足さなかった。値は作者の手順 4 で直す見積もりで、比べた案を持つ判断ではないからである | `315155b` |

違和感は次のように扱った。

- Codex 1：`pg_isready` の 3 秒 → Claude R2 と同じ。上の表のとおり直した
- Codex 2：`RESTARTS` が増えなくても、readiness の一時の失敗や 1 回だけの時間切れは分からない → 公開の配置で困るのは liveness の続けた失敗で作り直されることで、それは `RESTARTS` に出る。readiness の一時の失敗は Service から外れるだけなので、作者の手順は替えなかった
- Codex 3・Claude 1：計画の「いまはどのプローブも書いていない」と、「値の差し替え」の行は答えが来たら替えるという文が、直した後の状態と合わない → どちらも直した（`315155b`）
- Claude 2：同じ 1 行のコメントが 3 つのマニフェストと spec にある → どのファイルを開いた人にも理由が見えるので、そのままにした
- Claude 3：`web.yaml` で、`/up` のコメントの下に続けて置いた 1 行が、startupProbe だけに掛かるように見える → 中身は 3 つのプローブのどれにも当てはまるので、そのままにした
- Claude 4：5 秒が足りるかは実機でしか分からない → OI-182 と `deploy/README.md`「作者の手順」4 の `RESTARTS` で見る
- Claude 5：startupProbe の `timeoutSeconds` を `periodSeconds`（5 秒）より上げると、起動の上限が 3 分から延びる → いまの値では 3 分のままなので、直さなかった

### 実装の記録

#### 計画との違い

- `postgres` の `pg_isready` に `-t 4` を渡した（実装レビューの Claude R2）。計画は `timeoutSeconds: 5` だけを書いていたが、`pg_isready` が自分の既定の 3 秒で先に諦めると、`postgres` に効く猶予は 3 秒のままになるからである。計画のプローブの直しを、この形に合わせて直した。
- example は「明示する」だけでなく、プローブの組と、時間切れが既定の 1 秒より長いことと、`pg_isready` の `-t` がその内であることを確かめる（実装レビューの Codex R1・Claude R4）。
- `deploy/README.md`「作者の手順」4 は、取りまとめ役が作者の判断を書いた `4a14ee9` で `RESTARTS` を見ることを書いていたので、替えていない。

#### RED と、壊して落ちる記録

RED（期待の不一致で落ちたもの）：`spec/platform/deploy_manifests_spec.rb` に、すべてのプローブが `timeoutSeconds` を明示することを確かめる example を足し、マニフェストを変える前に流した（19 examples, 1 failure）。

```
Failure/Error: probes.each { |name, kind, probe| expect(probe["timeoutSeconds"]).to be_present, "#{name} の #{kind} が timeoutSeconds を書いていない" }
  frontend の readinessProbe が timeoutSeconds を書いていない
```

直しの後の版（`315155b`）で、マニフェストを 1 か所ずつ壊し、`bundle exec rspec spec/platform/deploy_manifests_spec.rb` を流して、scratchpad に置いた複製から戻した。戻した後に `cmp` で元と一致することを確かめた。

| 壊したもの | 落ちたもの |
|---|---|
| `web` の 3 つの `timeoutSeconds` を 1 にする | 1（`web の startupProbe の timeoutSeconds が 1`） |
| `web` の startupProbe を消す（キーの名前を替える） | 1（プローブの組の比較） |
| `frontend` の livenessProbe の `timeoutSeconds` を消す | 1（`frontend の livenessProbe の timeoutSeconds が nil`） |
| `postgres` の livenessProbe の `pg_isready` から `-t 4` を消す | 1（`postgres の livenessProbe の pg_isready -t が nil`） |
| `postgres` の `pg_isready` の `-t` を 5（`timeoutSeconds` と同じ）にする | 1（`postgres の readinessProbe の pg_isready -t が "5"`） |

#### 手元で流したもの

`315155b` の作業ツリーで、Ruby 3.4.11・PostgreSQL 18 で流した。

```sh
bundle exec rspec spec/platform/deploy_manifests_spec.rb spec/requests/sessions_spec.rb spec/platform/production_boot_spec.rb   # 33 examples, 0 failures
bin/check-open-items --due M41                                                                                                # 通った
bin/check-commit-refs                                                                                                         # 通った
bin/ci                                                                                                                        # すべての工程が通った。rspec は 2981 examples, 0 failures
kubectl kustomize deploy                                                                                                      # 7 つのプローブがどれも timeoutSeconds: 5 で描かれる
```

分岐の網羅率の警告は 0 件だった。kubeconform は手元に無いので、マニフェストの型の照合は CI の `manifests` のジョブで確かめた。

### 残件の処理

引当先が M41 の行は、OI-145〜OI-149・OI-181 が `decided`、OI-182・OI-183 が `judgment` で、`bin/check-open-items --due M41` が通る。OI-182 の判断（プローブの時間切れの明示）は、この節のとおり作った。作者の実機の確かめ（作るもの 9 の手順 1〜6）は台帳の行にせず、計画の M41 の「残り（サイクル 06）」の表の行のまま、作者が結果を PR か台帳に書くのを待つ。実装レビューから新しく積んだ残件と改善の候補は無い。
