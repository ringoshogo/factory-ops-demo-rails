# キューが詰まる

ジョブがキューに溜まるか失敗したまま残り、イベントの配送・メール・取り込みが遅れるときの手順。コマンドは、アプリと同じ環境変数を持つ場所（Web かワーカーのコンテナ）で流す。

## 警報

- `EventsQueueBacklog`：`events` のキューの待ちが 5 分続けて 1,000 件を超える
- `JobsFailed`：失敗したジョブが 10 分残る
- `EventDeliveryLagBudgetBurnFast`・`EventDeliveryLagBudgetBurnSlow`：イベントの配送が 60 秒を超えて遅れる割合が、誤差の予算を速く減らす（`../slo.md`「誤差の予算の消費」）

## 確かめること

1. キューごとの待ち・実行中・失敗の数を、ワーカーの exporter から読む。

   ```sh
   curl -s localhost:9395/metrics | grep -E '^queue_(ready|blocked|claimed|failed)_jobs'
   ```

2. 止めたキューが無いかと、キューごとの待ちの数を読む。止めたキューは、誰かが前の障害で止めたまま戻していないことがある。

   ```sh
   bin/rails runner 'puts "paused: #{SolidQueue::Pause.pluck(:queue_name).inspect}"; pp SolidQueue::ReadyExecution.group(:queue_name).count'
   ```

3. 失敗したジョブを、キューとジョブのクラスと例外のクラスで数える。同じ例外が並ぶなら、原因は 1 つである。

   ```sh
   bin/rails runner 'pp SolidQueue::FailedExecution.includes(:job).map { [ _1.job.queue_name, _1.job.class_name, _1.error["exception_class"] ] }.tally'
   ```

4. ワーカーのプロセスが動いているかを、心拍の時刻で確かめる。`config/queue.yml` のワーカーは、キューごとに別のプロセスである。心拍が古いプロセスは止まっている。

   ```sh
   bin/rails runner 'SolidQueue::Process.order(:kind).each { puts [ _1.kind, _1.name, _1.metadata&.dig("queues"), _1.last_heartbeat_at ].join(" ") }'
   ```

5. DB が詰まっていないかを、接続の状態ごとの数とロックの待ちで確かめる。問い合わせの本文は、`pg_read_all_stats` を持たないロールには他のロールの分が見えない。

   ```sh
   echo "SELECT usename, state, wait_event_type, count(*) FROM pg_stat_activity WHERE datname = current_database() GROUP BY 1, 2, 3 ORDER BY 4 DESC;" | bin/rails dbconsole -p
   ```

## 止血

キューはワーカーを分けている（`config/queue.yml`）ので、`events` の待ちが `imports` のジョブを待つことは無い。止血は原因で選ぶ。

- **ワーカーのプロセスが止まっている**：`bin/jobs` を起動し直す。心拍の途絶えたプロセスが持っていたジョブは、Solid Queue が失敗にする。
- **DB の負荷が原因**：重いジョブのキューを止めて、新しいジョブの受け取りを止める。実行中のジョブは止まらず、終わるまで走る。

  ```sh
  bin/rails runner 'SolidQueue::Queue.find_by_name("imports").pause'
  ```

- **同じ例外で失敗し続ける**：失敗したジョブはやり直さずに残し、原因を直すまで待つ。やり直しても同じ例外で失敗する。

## 復旧

原因を直してから、止めたキューを再開し、失敗したジョブをやり直す。イベントの受け手と送信のジョブは冪等なので、やり直してよい（`../architecture/data-model.md`「イベントの受け口と冪等キー」、`../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md` 決定 6）。

```sh
bin/rails runner 'SolidQueue::Queue.find_by_name("imports").resume'
bin/rails runner 'SolidQueue::FailedExecution.retry_all(SolidQueue::Job.where(id: SolidQueue::FailedExecution.select(:job_id)))'
```

取り込みのジョブ（`Imports::RunJob`）は、やり直す代わりに `imports:reenqueue` で登録し直してもよい（`import-stuck.md`）。

## 事後にすること

- 止めたキューが残っていないことを、確かめることの 2 で確かめる
- 失敗の原因と、やり直したジョブの数を障害の記録に残す
- 待ちの閾値（1,000 件）が早すぎたか遅すぎたかを、`../slo.md` の表と比べて見直す
