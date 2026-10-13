# サイクル 06 の計画レビュー：M42・M43・M44 と、M33・M41 の残りへの反映

この文書は、`implementation-plan.md` の M42・M43・M44 と、M33・M41 の「残り（サイクル 06）」を 2 系統の独立したレビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M42 から着手する担当者と、計画をレビューする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。

サイクル 06 に入るのは、サイクル 05 の改善の探索で起こした M42・M43 と、サイクル 05 から移した M33・M41 の残り（作者を待つ行）である。取りまとめ役は、レビューに出す前に 3 つを直した（`574a8e5`）。M33・M41 の残りに、作者を待つ行ごとの種類（答えで作るものが変わる問いか、値の差し替え・受け入れ・実機の確かめで済む問いか）と答えで替える場所を書いた（`guides/dev-cycle.md`「1. 計画レビュー」）。開いたままの Dependabot の PR 13 本（#15・#16・#61〜#71）を扱う M44 を起こした。M42 に、マニフェストの照合を amd64 のジョブに、GHCR への push を別のジョブに分ける既定を書いた。

初回のレビューは `574a8e5` を読んだ。依頼には読む版の commit を書き、その版を展開したディレクトリだけを読ませた。Claude は M42 に High を 1 件挙げて Conditional Go、Codex はどのマイルストーンも Go だった。High を直した版（`0715e0a`）を 2 系統で読み直し（読み直し 1）、Claude が直しの確かめ方に新しい High を 1 件挙げた。それを直した版（`59f0f91`）を読み直し（読み直し 2）、どちらも Go だった。読み直しで出た Medium 以下は、読み直しには出さずに直した。Claude のサブエージェントは、3 回とも最終報告を返さずに終わり、依頼に書かせた結果のファイルから読んだ（`guides/dev-cycle.md`「独立したレビュアー」）。Codex は一時の失敗を起こさず、出し直していない。

読む順は、マイルストーンの分け方 → マイルストーンごとの判定 → 指摘ごとの対応 → 指摘の根拠を確かめた結果 → 作者を待つ行 → 直さなかった指摘と台帳に積んだもの、である。指摘の出典は次の形で示す。2 系統の ID がぶつかるときは、`Codex M42-1` のように系統を添える。

| | Claude | Codex |
|---|---|---|
| 初回 | `<マイルストーン>-<番号>`（`M42-1` など） | `<マイルストーン>-<番号>` |
| 読み直し 1 | `R1-<マイルストーン>-<番号>` | `R1-<マイルストーン>-<番号>` |
| 読み直し 2 | `R2-<マイルストーン>-<番号>` | （指摘なし） |

## マイルストーンの分け方

| マイルストーン | 中身 | 分けた理由 |
|---|---|---|
| M42 CI のランナーの版を固定し、公開の配置のイメージを arm64 で組み立てる | `runs-on` の固定、`images` の arm64 のランナーへの移動、マニフェストの照合の `manifests`、GHCR への push の `publish` | サイクル 05 の改善の探索で、IB-94・IB-93・IB-91 を 1 つにまとめた |
| M43 公開の配置の作り直しを、本番の環境でだけ動かす | `DemoReset#run` の入口に本番の環境の条件を足す | サイクル 05 の改善の探索で、CI の変更と主題が違うので M42 から分けた |
| M44 依存の更新を取り込み、Dependabot の更新をまとめる | 開いた PR の更新を M44 のブランチで入れ、`dependabot.yml` に `groups` と `ignore` を置き、Node の主版をそろえる spec を足す | Dependabot の扱いは CI のランナーと主題が違い、M42 に入れると M42 の完了条件（ランナーと push の条件）と画面の依存の確かめが混ざる。M42 の後に置き、M42 が足したジョブの `uses:` もそろえる |
| M33 の残り | OI-144・OI-177〜OI-179 | サイクル 05 で実装レビューまで終え、作者を待つ行だけを移した |
| M41 の残り | OI-145〜OI-149・OI-181 と作者の実機の手順 | 同上 |

実装の順は M42 → M43 → M44 → M33・M41 の残りである。M44 は、M42 が足したジョブの `uses:` をそろえ、`package-lock.json` を変える PR で流れる `images` が arm64 に移った後に入る。M33・M41 の残りは、作者の答えが来た行から片付ける。

サイクル 06 は 5 つで、1 つのサイクルの上限（6 つ）に収まる（`guides/dev-cycle.md`「全体の流れ」）。

### Dependabot の PR の扱い

PR はマージも閉じもせず、M44 のブランチで同じ版を入れる（M44「作るもの 1」）。作者が M44 をマージすると、Dependabot は main で済んだ更新の PR を自分で閉じる。

| PR | 扱い |
|---|---|
| #15・#16・#63・#64（GitHub Actions の 4 つ） | 取り込む。M42 が足したジョブの `uses:` も同じ主版にそろえる |
| #62・#69（`react`・`react-dom` 19.3.0） | 組で取り込む。1 本ずつでは `npm ci` が ERESOLVE で落ちる（#69） |
| #61（`graphql` 17）・#70（`eslint` 10）・#68（`cn` 0.4） | 取り込む。1 つずつ commit を分け、各 commit で画面の検査を流す |
| #67・#71 | 取り込む |
| #66（`typescript` 7） | 取り込まない。`typescript-eslint` が TS 7 を受け付けない。`ignore` にせず開いたままにし、上げる時機は IB-99 で見る |
| #65（`@types/node` 26） | 取り込まない。画面の Node は 22 系で、`@types/node` の主版の上げを `ignore` にする |

## 判定

| マイルストーン | 初回 Claude | 初回 Codex | 読み直し 1 Claude | 読み直し 1 Codex | 読み直し 2 Claude | 読み直し 2 Codex |
|---|---|---|---|---|---|---|
| M42 | Conditional Go | Go | Conditional Go | Go | Go | Go |
| M43 | Go | Go | Go | Go | Go | Go |
| M44 | Go | Go | Go | Go | Go | Go |
| M33 の残り | Conditional Go | Go | Go | Go | Go | Go |
| M41 の残り | Go | Go | Go | Go | Go | Go |

全体の判定は、初回は Claude が Conditional Go、Codex が Go だった。Claude の M42-1 は High で、表に照らせば Conditional Go でよいが、`publish` の条件の式を変える直しなので読み直しに出した。読み直し 1 は、Claude が直しの確かめ方に新しい High（R1-M42-1）を挙げて Conditional Go、Codex は同じことを Medium にして Go だった。重大度は高い方を採り、直して読み直し 2 に出した。読み直し 2 は、2 系統とも前の High の解消を認め、新しい High 以上は無く、Go だった。読み直しは 2 回までと決めているので、ここで終えた。M42 から着手できる。

2 系統が同じことを挙げた指摘は次の 2 つである。

- PR の契機で `publish` を流しても、push のときの経路（`image_inputs` の skip）を通らない（Claude M42-2・Codex M42-1。どちらも Medium）
- 確かめの一時の commit で `ci_checks_spec.rb` を落とすと、`test` が落ちて確かめが成り立たない（Claude R1-M42-1 は High、Codex R1-M42-1 は Medium）

## 指摘と対応

重大度は、2 系統で違うときは高い方を採った。「直した節」は、断りが無ければ `implementation-plan.md` の節である。各表は、初回、読み直し 1、読み直し 2 の順に並べる。

### M42

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M42-1 | High | `publish` の `if:` にジョブの名前を並べると、`needs` に足したジョブを `if:` に足し忘れたとき、そのジョブが落ちても push する。spec は `needs` しか守らない | 作るもの 3。`if:` を `!cancelled()` と `needs.*.result` に `failure`・`cancelled`・`skipped` を含まないことの式にし、名前に頼らない形にした。`needs` が全ジョブを持つことは spec がワークフローの `jobs` から集めて守る |
| Claude M42-2・Codex M42-1 | Medium | PR の契機に `publish` を足す確かめでは、`image_inputs` が成功するので、push の経路を通らない | 完了条件。M42 のブランチを `on.push.branches` に一時に足し、ブランチへの push で 3 回（すべて成功、`test` を落とす、`!cancelled()` を外す）確かめる形にした |
| Claude M42-3 | Medium | 最初の main への push の `publish` を次のマイルストーンの前に確かめる文が、PR の積み重ねと合わない | 完了条件。取りまとめ役がサイクル 06 の振り返りで確かめ、作者は適用の前に GHCR の 2 つのイメージを確かめる（いまの手順）とした |
| Claude M42-4 | Low | `runs-on` の名前を完全一致で照らすか、版の形で照らすかが決まらない | 作るもの 1。`/\Aubuntu-\d{2}\.\d{2}(-arm)?\z/` で照らし、`images` と `publish` が `-arm` を持つことも確かめる |
| Claude M42-5 | Low | `deploy/README.md` の 2 か所と `config.md` の 1 か所が、「文書に残すこと」の名指しの外に残る | 文書に残すこと。3 か所を足し、「`images` のジョブ」と「QEMU」を `git grep` で数えて直すと書いた |
| Claude M42-6 | Low | ワークフローの最上位に `permissions` が無く、権限がリポジトリの設定に依る | 作るもの 3。最上位を `contents: read` にし、最上位に `packages: write` が無いことを spec で確かめる |
| Claude R1-M42-1・Codex R1-M42-1 | High | 一時の commit で `ci_checks_spec.rb` を落としてよいとすると、`test` が落ち、3 回の確かめのうち 2 回が成り立たない | 作るもの 3 と完了条件。`publish` のログインと push のステップに、いつも `if: github.ref == 'refs/heads/main'` を書く形にした。一時の commit は契機を足すだけで、spec はどの一時の commit でも通る。どの回も、ほかのジョブの結果を実行の画面で見て URL を証跡に書く |
| Claude R1-M42-2 | Low | 3 回目で `publish` が走ったときの扱いが無い | 完了条件。走っても `!cancelled()` を残し、見た結果を判断に書く |
| Claude R1-M42-4 | Low | ブランチへの push の `lint` は前の先端を基準にするので、force push を挟むと落ちる | 完了条件。3 回は force push を挟まずに続けて push する |
| Claude 読み直し 1 の違和感 | Low | 一時の契機を戻し忘れると、ブランチへの push でも `publish` が流れ続ける | 完了条件。戻した commit で `on.push.branches` が `[ main ]` だけであることを証跡に書く |
| Claude R2-M42-1 | Low | 2 回目に足す落ちる example の置き方で、`lint` か `bin/test-layers` も落ちうる | 完了条件。既存の spec のファイルに、RuboCop に当たらない example を 1 つ足すと書いた |
| Claude R2-M42-2 | Low | ステップの `if:` を書き誤ると、main への push で何も置かれないまま `publish` が成功する | 完了条件。振り返りの確かめで、ログインと push のステップが skip でなく実行されたことも見る |
| Claude R2-M42-3 | Low | ステップの `if:` の理由を残す場所が無いと、冗長な条件に見えて消されうる | 文書に残すこと。`publish` の直前のコメントに、ジョブの `if:` とステップの `if:` の理由を書く |

### M44

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Codex M44-1・Claude M44-2 | Medium | 正本の `engines` の `>=22.12` は 24 系も許し、主版を 1 つに決めない。最初に落とす example を `fetch` で書くと期待の不一致にならない | 作るもの 3 と完了条件。`engines` を `^22.12` に直し、`^<主版>.<小版>` の形を spec で確かめる。example を `all(include("groups"))` の形で書く。`node-version` の無い setup-node のステップを落とし、整数と文字列の両方から主版を読む |
| Codex M44-2 | Medium | spec が `groups` の有無しか見ず、まとまりの中身・順・`ignore` の抜けが通る | 作るもの 4 を足した。小版と修正版のまとまりの `update-types`、組のまとまりの対象と順、0 系の除外、github-actions の `*`、`@types/node` の `ignore` を確かめ、3 つの壊し方の記録を求めた |
| Claude M44-3 | Medium | TS 7 の見送りの理由（peer の範囲）が #66 の CI の事実（実行の時の拒否）と合わず、`ignore` にすると上げる時機を知らせる者がいない | 作るもの 1・2。理由を実行の時の拒否に直し、`typescript` を `ignore` にしない |
| Claude M44-1 | Low | `npm ls --all` が失敗で終わることの根拠が無く、`npm ci` の後では捕まえるものが無いかもしれない | 完了条件。npm の `lib/commands/ls.js` の `ELSPROBLEMS` を引き、`--legacy-peer-deps` で組の依存をずらした木で落ちることを記録させる |
| Claude M44-4 | Low | 作業中に開く PR と、作者が先に Dependabot の PR をマージした場合の扱いが無い | 作るもの 1 と作者の手順。着手の時点で PR を読み直し、作者には M44 をマージするまで Dependabot の PR をマージしないよう求める |
| Claude M44-5 | Low | 0 系の `cn` を、取り込みでは主版と同じに扱い、`groups` ではまとめる | 作るもの 2。0 系の依存を小版と修正版のまとまりの `exclude-patterns` に入れ、組のまとまりが主版を含むことを書いた |
| Claude の違和感 | Low | `frontend/Dockerfile` の Node の版のコメントが、M44 の後は spec の規則になる | 文書に残すこと。コメントを正本と spec に合わせる |
| Claude R1-M44-1 | Medium | #66 を開いたままにしても、`typescript-eslint` を上げたときに #66 の CI は流れ直さず、知らせにならない | 作るもの 1。知らせの文を外し、上げる時機を改善の候補 IB-99 に積んだ |
| Claude R1-M44-2 | Low | 作者の手順が PR を番号で名指すが、`groups` を入れた後に番号が変わりうる | 作者の手順。中身（`typescript` 7、`@types/node` 26）で名指した |

### M33 の残り

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M33-1 | Medium | OI-179 は、どちらの答えでも作るもの（1 つの関数）の形が同じで、値の差し替えに当たる | 直さなかった（下の「直さなかった指摘」）。待つ理由を、残りの表の OI-179 の行と台帳の OI-179 に書いた |
| Claude M33-2 | Low | OI-177 の指摘が API に及ぶかを、誰がいつ判定するかが無い | 残りの表の OI-177。取りまとめ役が台帳に写すときに指摘ごとに書き、API に及ぶものだけを差分の計画レビューに通す |
| Codex の違和感 | Low | M33 の残りの大きさは、OI-144・OI-177 の答えで大きくなりうる | 残りの節の冒頭。差分の計画レビューで、1 回の作業に収まるかとサイクルの上限を見直す（IB-67） |

### M41 の残り

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| Claude M41-1 | Low | OI-149 で既定と違う答えのときは、コードと spec と文書を消す変更になる | 残りの表の OI-149。消す変更は、差分の計画レビューには出さず、実装レビューに通す |
| Claude M41-2 | Low | OI-147 の 4GB のとき、limits を下げるか、ワーカーを Puma の中に移すかを、何で決めるかが無い | 残りの表の OI-147 と台帳。まず測った値で limits を下げ、`free -h` の総量に収まるかで決め、収まらなければ Puma の中へ移して計画レビューに通す |

M43 には、どの回も指摘が無かった。

## 指摘の根拠を確かめた結果

指摘の根拠は、リポジトリのファイルと、レビュアーが引いた公式の文書で確かめた。

| 根拠 | 結果 |
|---|---|
| 状態の関数を書かない `if:` には、暗黙の `success()` が足される（M42-1・M42-2） | 正しい。GitHub の文書の式の状態の関数「A default status check of `success()` is applied unless you include one of these functions.」。依存の連なりの skip は、ワークフローの構文の `jobs.<job_id>.needs`「a failure or skip applies to all jobs in the dependency chain from the point of failure or skip onwards」（Claude が読み直し 2 で引いた） |
| `needs.<job_id>.result` の値は 4 つ（M42-1） | 正しい。GitHub の文書の文脈「Possible values are `success`, `failure`, `cancelled`, or `skipped`.」。`needs.*.result` は直接の `needs` の結果の配列になり、`contains` は配列の要素を見る（2 系統が読み直し 1 で引いた） |
| `test` のジョブは `spec/platform/` を含む rspec の全件を流す（R1-M42-1） | 正しい。`.github/workflows/ci.yml` の `test` と、`.rspec` に除外が無いこと |
| `react-dom` 19.3.0 は peer に `react` ^19.3.0 を求める（M44 の作るもの 1） | 正しい。#69 の CI の `frontend` のログの `npm error peer react@"^19.3.0" from react-dom@19.3.0` |
| TS 7 は実行の時に拒まれる（Claude M44-3） | 正しい。#66 の CI の `frontend` のログは、`npm ci` を通った後に「Error: typescript-eslint does not support TS 7.0.」で落ちた |
| `engines` の `>=22.12` は 24 系も許す（Codex M44-1） | 正しい。`frontend/package.json` の `engines` |
| Dependabot は依存を最初に当たったまとまりに入れる（Codex M44-2） | 正しい。GitHub の文書の Dependabot の設定「If a dependency matches more than one rule, it's included in the first group that it matches.」 |
| `npm ls` は範囲に合わない依存で失敗で終わる（Claude M44-1） | Codex が npm の `lib/commands/ls.js` の `ELSPROBLEMS` を引いた。Claude は npm の文書に終了コードの記述が無いとした。M44 の壊して落ちる記録で確かめる |

## 作者を待つ行

作者を待つ行は、どれも取りまとめ役が決めない。答えが来たら、取りまとめ役が台帳の結果の欄に書き、行の ID を担当に伝える。種類は台帳の各行と、`implementation-plan.md` の M33・M41 の「残り（サイクル 06）」の表に書いた。

### 答えで作るものが変わる問い

答えが来るまで、その部分に着手しない。答えが既定と違えば、取りまとめ役が作るものを節に書き、差分を計画レビューに通してから実装者に渡す。

| ID | 問い | 既定 | 答えが既定と違えば作るもの |
|---|---|---|---|
| OI-144 | 一覧の並べ替えの列を、一覧の表の列に限るか | 限る（作るものは無い） | 並べたい値を一覧の表に写す列、`orderBy` の列、行列と S1 の行、画面の見出し |
| OI-177 | 画面の細かい指摘（作者が動かした後に出す） | — | 指摘ごとの画面とテスト。API に及ぶ指摘は計画レビューに通す |
| OI-179 | 品番照合待ちを含む受注の合計金額を、出さないか一部を出すか | —（いまの画面は 2 つの形が混ざる） | 答えの形の 1 つの関数と、ダッシュボード・受注一覧・受注詳細の呼び出し |
| OI-148 | 公開の配置で訪問者に許す操作 | すべて許す（作るものは無い） | 公開の配置でだけ操作を止める仕組み |
| OI-147（4GB の機種のとき） | Raspberry Pi の機種とメモリ | 8GB とみなす | 測った値で limits を下げても収まらなければ、ワーカーを Web の Puma の中で動かす形 |

### 値の差し替え・受け入れ・実機の確かめで済む問い

既定で作ってあるか、既定で作る。答えが来たら値だけを替える。答えが来なければ、残りを次のサイクルへ移す。

| ID | 問い | 既定 | 替える場所 |
|---|---|---|---|
| OI-145 | 公開の画面のホスト名 | `factory-ops-rails.hayatec.dev` | `deploy/kustomization.yaml` の `host` |
| OI-146 | 毎日の作り直しの時刻と、Raspberry Pi を夜に止めているか | 日本時間の 4:30、6 時間の内なら起動の後に流す | `deploy/daily-reset.yaml` |
| OI-147（8GB 以上の機種のとき） | Raspberry Pi の機種とメモリ（`free -h` の値） | 8GB とみなす | 作者の手順 4 で測った値で、各コンテナの requests と limits |
| OI-149 | 共有のアカウントのログアウトで、ほかのセッションを切るか | 切らない（`SHARED_DEMO_ACCOUNTS=1`） | `deploy/web.yaml`。いまのままを選んだら、使わなくなる分岐と example と文書の文も消す |
| OI-178 | 発注詳細の取消依頼のボタンを出す発注の状況 | `SENT`・`AWAITING_SUPPLIER_CONFIRMATION`・`ACCEPTED`・`INBOUND` | `frontend/lib/purchase-order-flow.ts` の集合（M33 の残りで既定のまま移す） |
| OI-181 | public のリポジトリに LICENSE を置くか | 置かない | 根の `LICENSE` と `README.md` |
| — | 作者の実機の手順 | — | `deploy/README.md`「作者の手順」1〜6。結果を PR か台帳に書くまで公開しない |
| — | 取り込まなかった Dependabot の PR を閉じる | — | M44 をマージした後、`@types/node` 26 の PR と、Dependabot に閉じられずに残った PR を閉じる。`typescript` 7 の PR は開いたままにする。M44 をマージするまで Dependabot の PR をマージしない |

## 直さなかった指摘と、台帳に積んだもの

- Claude M33-1（OI-179 は値の差し替えに当たる）：作るものの形はどちらの答えでも同じだが、既定を置くと、いま動いている 2 つの画面のどちらかの表示を、作者の答えの前に取りまとめ役が変えることになる。作者の判断を取りまとめ役が先に下さないため、答えで作るものが変わる問いのまま待つ。Claude の判定の条件（振り分けを残す理由を表に書けば Go）どおりに、理由を表と台帳に書き、読み直し 1 で 2 系統とも解消と判定した
- Claude R1-M42-3（`if:` の式を spec で守らない）：`guides/config.md`「CI の工程」の方針（YAML の式を文字列で照らす spec を置かず、配線を変えた PR は手で確かめる）どおりなので直さない
- 改善の候補に積んだもの：Claude 読み直し 1 の R1-M44-1 から、TypeScript を 7 系に上げる時機を見る IB-99
- 違和感は、どれも計画の直しで扱った（IB-93 の効き目を改善の探索がどの値で判定するかは M42 の完了条件に、Dependabot が `groups` の後に PR を開き直すことは M44 の作者の手順に、`frontend/Dockerfile` のコメントは M44 の文書に残すことに、M33 の残りの大きさは残りの節の冒頭に書いた）
