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
