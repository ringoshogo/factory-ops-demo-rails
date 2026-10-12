# SendGrid の障害・429 の連続

メールの送信先の SendGrid が失敗を返すか、送信の上限（429）を返し続け、受領請求書の通知が届かないときの手順。送信のジョブの応答の扱いは `../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md` 決定 5 の A-2 にある。コマンドは、アプリと同じ環境変数を持つ場所で流す。ワーカーの exporter（9395）を読む確かめることの 1 は、ワーカーのコンテナで流す。

## 警報

- `ReceivedInvoiceNotificationFailed`：受領請求書の通知が、再試行しない応答（400・401・403・413）か、再試行を使い切って失敗した
- `SendgridRateLimited`：外部の呼び出しの 429 の割合が 10 分続けて 20% を超える
- `ReceivedInvoiceAcceptanceBudgetBurnFast`・`ReceivedInvoiceAcceptanceBudgetBurnSlow`：受領請求書の通知の受け付けが 15 分を超える割合が、誤差の予算を速く減らす（`../slo.md`「誤差の予算の消費」）

## 確かめること

1. 応答の種類の内訳と、失敗と捨てた通知の理由を、ワーカーの exporter から読む。`status` は `2xx`・`429`・`4xx`・`5xx`・`timeout`（接続の失敗を含む）に分かれる。

   ```sh
   curl -s localhost:9395/metrics | grep -E '^(external_requests_total|notification_failures_total|notification_dropped_total)'
   ```

2. 応答の種類と失敗の理由（`reason`）で、原因を分ける。再試行を使い切った失敗の理由は、最後の応答に `retries_exhausted:` を前に付けたものである。
   - `reason` が `http_401`・`http_403`・`missing_api_key`：API キーが誤っているか失効している。自社の設定の誤りなので、ほかの送信もすべて失敗している
   - `status` が `429`：送信の上限に当たっている。ジョブは応答が示す待ち時間の後にやり直す
   - `status` が `5xx`・`timeout`：SendGrid の障害か、ネットワークの障害である。SendGrid の障害の告知を確かめる
3. `external_mail` のキューの待ちと、止めていないかを読む。

   ```sh
   bin/rails runner 'q = SolidQueue::Queue.find_by_name("external_mail"); puts [ q.size, (q.paused? ? "paused" : "running") ].join(" ")'
   ```

## 止血

- **401・403**：送っても失敗するだけなので、`external_mail` のキューを止める。止めても実行中のジョブは止まらない。

  ```sh
  bin/rails runner 'SolidQueue::Queue.find_by_name("external_mail").pause'
  ```

- **429 が続く**：`external_mail` のキューを止め、応答の待ち時間（`Retry-After` か `X-RateLimit-Reset`）が過ぎてから再開する。SendGrid への同時の送信の上限は、送信のジョブのクラスに書いた `limits_concurrency`（2 つ）で、下げるにはデプロイが要る。
- **5xx・タイムアウト**：ジョブが間隔を延ばしながらやり直すので、キューは止めない。障害が長引き、再試行を使い切った通知が増えるなら、401・403 と同じく止める。

撃ちっぱなしの通知（新しい受注の知らせ）は、失敗すると捨て、送り直さない。

## 復旧

1. 原因を直す。API キーは credentials の `sendgrid.api_key` にある（`../guides/config.md`「使っていない機能の設定」）。直したらデプロイし直す。
2. 止めたキューを再開する。

   ```sh
   bin/rails runner 'SolidQueue::Queue.find_by_name("external_mail").resume'
   ```

3. 再試行を使い切ったか、再試行しない応答で失敗した確実な通知を、障害の始まりの時刻から送り直す。同じ送信記録のジョブを登録し直すので、受け付け済みの通知は送らない。

   ```sh
   SINCE=2026-10-12T09:00:00+09:00 bin/rails notifications:redeliver
   ```

## 事後にすること

- 送り直した件数（`notifications:redeliver` の出力）と、送り直さなかった撃ちっぱなしの通知の数（`notification_dropped_total`）を障害の記録に残す
- 429 が続いたなら、送信の上限と同時実行の上限（2 つ）が合っているかを見直す
