# GraphQL の操作が遅いか失敗する

発注の登録か画面の問い合わせが、SLO の閾値（`../slo.md`「SLO」）を超えて遅くなるか、トップレベルのエラーで失敗するときの手順。コマンドは、アプリと同じ環境変数を持つ場所で流す。

## 警報

- `PlacePurchaseOrderLatencyBudgetBurnFast`・`PlacePurchaseOrderLatencyBudgetBurnSlow`：発注の登録が 500 ms を超える割合が、誤差の予算を速く減らす
- `PlacePurchaseOrderErrorBudgetBurnFast`・`PlacePurchaseOrderErrorBudgetBurnSlow`：発注の登録の失敗（`outcome="error"`）の割合が、誤差の予算を速く減らす
- `ScreenQueryLatencyBudgetBurnFast`・`ScreenQueryLatencyBudgetBurnSlow`：画面の問い合わせが 1 秒を超える割合が、誤差の予算を速く減らす

## 確かめること

1. どの操作が遅いか、どのコードで失敗しているかを、Web の exporter から読む。遅い操作は、`le` の小さいバケットの数が `_count` より少ない。失敗は `graphql_top_level_errors_total` の `code` で分かれ、`none` は解析の失敗のようにコードを持たないエラーである。

   ```sh
   curl -s localhost:9394/metrics | grep -E '^graphql_operation_duration_seconds_(count|bucket\{.*le="(0.5|1)")'
   curl -s localhost:9394/metrics | grep -E '^graphql_top_level_errors_total'
   ```

2. 失敗した操作のイベントを引く。`graphql.operation_completed` の `result` が `error` の行は、`error_codes` にトップレベルのエラーのコードを、`context` に相関 ID を持つ。例外で失敗した要求は、エラー通知にも出る。本番はログの基盤で、開発の環境では次で引く。

   ```sh
   grep '"name":"graphql.operation_completed"' log/events.log | grep '"result":"error"' | tail -20
   ```

3. DB が詰まっていないかを、長く走る問い合わせとロックの待ちで確かめる。問い合わせの本文は、`pg_read_all_stats` を持たないロールには他のロールの分が見えない。

   ```sh
   echo "SELECT pid, usename, state, wait_event_type, wait_event, now() - query_start AS running, pg_blocking_pids(pid) AS blocked_by, left(query, 80) AS query FROM pg_stat_activity WHERE datname = current_database() AND state <> 'idle' ORDER BY running DESC NULLS LAST LIMIT 20;" | bin/rails dbconsole -p
   ```

4. 遅くなり始めた時刻と、デプロイの時刻を比べる。

## 止血

- **デプロイの後から遅いか失敗する**：前の版に戻す。
- **取り込みが DB に負荷をかけている**（確かめることの 3 で、取り込みのジョブの問い合わせが長く走るか、ロックを持っている）：`imports` のキューを止める。実行中のジョブは止まらない（`queue-backlog.md`「止血」）。
- **特定の操作だけが失敗する**：その操作を使う画面の利用者に知らせる。操作ごとに止める切り替えは無い。

## 復旧

原因を直してデプロイし、止めたキューを再開する（`queue-backlog.md`「復旧」）。1 時間の窓の割合が閾値の下に戻ると、速い方の警報が止む。

## 事後にすること

- 遅くなった操作の問い合わせを、クエリ数の予算（`spec/graphql/query_budget_spec.rb`）と、問い合わせの複雑度（`spec/graphql/query_complexity_spec.rb`）で捕まえられたかを見直す
- 消費した誤差の予算と、SLO の値が実際の使われ方に合っているかを、`../slo.md` の表と比べて見直す
