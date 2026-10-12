# 取り込みが進まない

受注側が始めた CSV の取り込みが、待機中や反映中のまま終わらないときの手順。取り込みの段階と再開の仕組みは `../adr/007-非同期処理の型をジョブを失ったときの影響で選ぶ.md` 決定 5 の A-4 と `../architecture/data-model.md`「取り込み（`imports`）」にある。コマンドは、アプリと同じ環境変数を持つ場所で流す。

## 警報

- `ImportStalled`：`imports` のキューに実行中のジョブが 15 分続けてあり、その間に反映した行が増えない
- `SmallImportDurationBudgetBurnFast`・`SmallImportDurationBudgetBurnSlow`：10,000 行以下の取り込みが 5 分を超える割合が、誤差の予算を速く減らす（`../slo.md`「誤差の予算の消費」）
- 利用者からの問い合わせ（`supplier.import` の状況が変わらない）

## 確かめること

1. 取り込みのジョブを新しい順に並べ、状態（`ready`・`claimed`・`blocked`・`failed`・`finished` など）と引数（取り込み ID・テナント ID）を読む。`blocked` は、同じテナントの別の取り込みが終わるのを待っている。テナントごとに 1 つずつ動かすからである。

   ```sh
   bin/rails runner 'SolidQueue::Job.where(class_name: "Imports::RunJob").order(id: :desc).limit(20).each { puts [ _1.id, _1.status, *_1.arguments["arguments"] ].join(" ") }'
   ```

2. 止まった取り込みの行を、ジョブの引数のテナントで開いて読む。状況は時刻列から決まる（`../architecture/data-model.md`「取り込み（`imports`）」）。`staged_rows` は置き場へ写した最後の行番号で、見出しを 1 行目に数える。

   ```sh
   TENANT_ID=<テナント ID> IMPORT_ID=<取り込み ID> bin/rails runner 'Tenancy.with_tenant(ENV.fetch("TENANT_ID")) { pp ActiveRecord::Base.connection.select_one("SELECT kind, total_rows, applied_rows, failed_rows, started_at, staged_at, finished_at, failed_at, failure_reason, (SELECT max(row_number) FROM import_rows WHERE import_id = imports.id) AS staged_rows FROM imports WHERE id = $1", "import", [ ENV.fetch("IMPORT_ID") ]) }'
   ```

3. 失敗したジョブの例外を読む。`SolidQueue::Processes::ProcessPrunedError` は、ワーカーのプロセスが強制終了したことを示し、Solid Queue は自動ではやり直さない。

   ```sh
   bin/rails runner 'SolidQueue::FailedExecution.joins(:job).where(solid_queue_jobs: { class_name: "Imports::RunJob" }).each { puts [ _1.job_id, *_1.job.arguments["arguments"], _1.error["exception_class"], _1.error["message"] ].join(" ") }'
   ```

4. 中断と再開を繰り返しているなら、取り込みの ID でログを引く。取り込みのイベント（`imports.chunk_applied`・`imports.finished`）は `import_id` を持ち、`context` の `job_id` から同じジョブの開始と終わりの行（`active_job.started`・`active_job.completed`）を引ける（`../guides/config.md`「イベントごとに書く項目」）。本番はログの基盤で、開発の環境では次で引く。

   ```sh
   grep '<取り込み ID>' log/events.log | tail -20
   ```

## 止血

取り込みは、イベントの配送とメールとは別のワーカーで動くが、全テナントの取り込みが `imports` のキューの 1 つのワーカー（1 プロセス・1 スレッド。`config/queue.yml`）を共有する。止まった取り込みのジョブが実行中のまま残ると、同じテナントの次の取り込み（`blocked`）だけでなく、他社の取り込み（`ready`）も待たせる。確かめることの 1 で他社のジョブが待っていれば、止まったジョブを持つワーカーのプロセス（`queue-backlog.md`「確かめること」の 4）を止めて起動し直し、下の復旧で登録し直す。ワーカーそのものが DB に負荷をかけているなら、`queue-backlog.md`「止血」のとおり `imports` のキューを止める。

## 復旧

- **ジョブを失った**（ジョブが無いか `failed` で、取り込みが待機中・置き場へ写し中・反映中のまま）：新しいジョブを登録する。新しいジョブは置き場の状態から続きを作り直し、結果のある行を飛ばすので、反映は行ごとに 1 回になる。動いているジョブが残っていても、新しいジョブはテナントの上限で待つので、結果は変わらない。

  ```sh
  IMPORT_ID=<取り込み ID> TENANT_ID=<テナント ID> bin/rails imports:reenqueue
  ```

  失敗したジョブは、登録し直した後に捨てる。捨てずに `queue-backlog.md`「復旧」でやり直すと、同じ取り込みのジョブが 2 つになる。2 つでも結果は変わらないが、テナントの次の取り込みを待たせる。

  ```sh
  bin/rails runner 'SolidQueue::FailedExecution.find_by!(job_id: <失敗したジョブの ID>).discard'
  ```

- **取り込み全体が失敗した**（`failed_at` がある）：やり直さない。`failure_reason` の理由（見出しの誤り・行数の上限・文字コード・CSV の形・役割）を利用者に伝え、直したファイルを置き直してもらう。
- **置いたまま中身を消したファイル**：置いてから 24 時間を過ぎて取り込みを始めなかったファイルは、中身を消してあり、`startImport` は `CONFLICT` を返す。利用者にファイルを置き直してもらう。

## 事後にすること

- 登録し直した取り込みが完了か一部失敗になったことを、確かめることの 2 で確かめる
- ワーカーが強制終了した原因（メモリの上限・デプロイの止め方）を障害の記録に残す
