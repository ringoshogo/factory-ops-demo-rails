# SLO と警報

運用者は、利用者が待たされているか、届くはずのものが届いていないかを、アプリのメトリクス（`guides/config.md`「メトリクス」）で測る。主な操作ごとに、28 日のうちどれだけの割合を目標の範囲に収めるか（SLO）を決め、外れそうな速さで外れ始めたら警報を出す。警報を受けた人は、警報に書いた手順書を開いて対処する。

この文書は、警報を受けた人が「この警報は何を測っているか」を引くときと、SLO の値を見直す人が読む。

## SLO

値は初めの目安である。30 日の実測の後に見直す。

| SLI | 測り方 | SLO（28 日） |
|---|---|---|
| 発注の登録の速さ | `graphql_operation_duration_seconds{operation="PlacePurchaseOrder"}` が 500 ms 以内の割合 | 95% |
| 発注の登録の成功 | 同じ操作で `outcome` が `error` でない割合。入力の誤り（`user_error`）は成功に数える | 99.5% |
| 画面の問い合わせの速さ | `operation_type="query"` で `operation` が `other` でない操作が 1 秒以内の割合 | 95% |
| イベントの配送の遅れ | `event_delivery_lag_seconds` が 60 秒以内の割合 | 99% |
| 確実な通知の受け付け | `notification_acceptance_seconds{kind="received_invoice"}` が 15 分以内の割合 | 99% |
| 取り込みの完了 | `import_duration_seconds{size="small"}` が 5 分以内の割合 | 95% |

閾値はどれも、ヒストグラムのバケットの境界にある。閾値を変える人は、`config/initializers/metrics.rb` のバケットも同じ変更で直す。境界に無い閾値は、割合を取れない。

## 警報

警報の規則は `config/prometheus/alerts.yml` にある。警報は 2 種類で、重さ（`severity`）で受け方が分かれる。`page` は受けた人がすぐに対処し、`ticket` は営業時間の中で対処する。

### 誤差の予算の消費

SLO が許す外れ（1 − SLO）を、誤差の予算と呼ぶ。SLO ごとに、窓の中で外れた要求の割合を記録の規則で取り、それが予算を減らす速さで鳴らす。

| 窓 | 鳴らす速さ | 重さ |
|---|---|---|
| 1 時間 | 28 日の予算の 2% を 1 時間で消費する（13.44 倍） | `page` |
| 6 時間 | 28 日の予算の 5% を 6 時間で消費する（5.6 倍） | `ticket` |

倍率は「消費する割合 × SLO の期間の時間数（28 日は 672 時間）÷ 窓の時間数」である。SLO の期間を変える人は、倍率も直す。要求の無い窓は割合が出ないので、鳴らない。

### 状態の警報

割合では遅れて見えるか、件数が少なくて割合にならない障害は、状態で鳴らす。

| 警報 | 条件 | 重さ |
|---|---|---|
| `JobsFailed` | 失敗したジョブ（`queue_failed_jobs`）が 10 分続けて残る | `ticket` |
| `EventsQueueBacklog` | `events` のキューの待ち（`queue_ready_jobs`）が 5 分続けて 1,000 件を超える | `page` |
| `ReceivedInvoiceNotificationFailed` | 受領請求書の通知の失敗（`notification_failures_total`）が増えた | `page` |
| `SendgridRateLimited` | 外部の呼び出しの 429 の割合が 10 分続けて 20% を超える | `ticket` |
| `ForbiddenByObjectOrUndeclared` | 出どころが `object` か `undeclared` の `FORBIDDEN` が増えた | `page` |
| `ImportStalled` | `imports` のキューに実行中のジョブが 15 分続けてあり、その間に反映した行（`import_rows_total`）が増えない | `ticket` |

`FORBIDDEN` の警報は、出どころ（`guides/config.md`「メトリクスとラベル」の `reason`）で絞る。返すオブジェクトの規則の拒否（`object`）は scope と規則の食い違いで、テナントの境界の不具合の兆しである。宣言の無い拒否（`undeclared`）は、宣言を忘れた入口が本番に出た兆しである。`member` が `admin` に限る操作を呼んだ拒否（`rule`）は、画面がボタンを隠していても起こりうる利用者の操作なので、鳴らさない。

カウンタが「増えた」警報は、窓の中の増加と、10 分前に無かった 0 でない系列の 2 つで見て、2 分続いたら鳴らす。カウンタの系列は最初に数えたときに現れるので、プロセスの起動の後の最初の 1 件は増加に現れない。2 分待つのは、収集が 1 回抜けて 10 分前の値が欠けたときに、値の変わらない系列を新しい系列と取り違えないためである。

取り込みの停滞は、1 分ごとに「実行中なら 1、実行中でないか系列が無ければ 0」にした値の 15 分の最小値で、実行中が途切れずに 15 分続いたことを確かめる。系列の値の最小値をそのまま取ると、窓の中にあるサンプルだけで決まるので、収集が途切れた後やワーカーを起こし直した直後に、実行中が 1 分でも鳴る。

## 警報と手順書

どの警報も `annotations.runbook` に手順書のパスを持つ。手順書は `runbooks/` にあり、警報を受けた人が上から順に読む節（警報 → 確かめること → 止血 → 復旧 → 事後にすること）を持つ。`spec/platform/alerts_runbook_spec.rb` が、どの警報も手順書を指し、どの手順書もどれかの警報から指され、節がその順にあることを確かめる。

| 手順書 | 障害 | 指す警報 |
|---|---|---|
| `runbooks/graphql-degradation.md` | GraphQL の操作が遅いか失敗する | 発注の登録と画面の問い合わせの予算の消費 |
| `runbooks/queue-backlog.md` | キューが詰まる | イベントの配送の遅れの予算の消費・`JobsFailed`・`EventsQueueBacklog` |
| `runbooks/sendgrid-outage.md` | SendGrid の障害・429 の連続 | 確実な通知の受け付けの予算の消費・`ReceivedInvoiceNotificationFailed`・`SendgridRateLimited` |
| `runbooks/import-stuck.md` | 取り込みが進まない | 取り込みの完了の予算の消費・`ImportStalled` |
| `runbooks/rls-misconfiguration.md` | RLS の設定の誤りが疑われる | `ForbiddenByObjectOrUndeclared` |

## 規則を変える人が確かめること

警報の規則を変える人は、`bin/check-alerts` を流す。`promtool check rules` が式を、`promtool test rules` が `config/prometheus/alerts_test.yml` の系列で鳴ることと鳴らないことを確かめる。promtool はホストに入れず、版を固定した Prometheus のイメージで流す。CI も同じスクリプトを流す。

ヒストグラムの `le` は、Prometheus 3 が取り込みの時に浮動小数の表記にそろえる（`le="1"` は `le="1.0"` になる）ので、規則とテストはその表記で書く。表記が違うと、バケットの系列が見つからずに割合が空になり、警報が黙って鳴らなくなる。

SLO の値を見直したら、この文書の表と、`alerts.yml` の記録の規則と閾値と、`alerts_test.yml` の境目の系列を、同じ変更で直す。
