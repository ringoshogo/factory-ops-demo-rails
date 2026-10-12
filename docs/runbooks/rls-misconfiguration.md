# RLS の設定の誤りが疑われる

あるテナントの利用者が他社の行を読めたか書けた疑いがあるときの手順。本デモは、テナントの境界を RLS（PostgreSQL の行単位のセキュリティ）と公開 API の scope の 2 つで守る（`../architecture/data-model.md`「RLS」、`../architecture/graphql-schema.md`「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。どちらかが崩れた兆しを見たら、疑いが消えるまで業務の入口を止めてから調べる。コマンドは、アプリと同じ環境変数を持つ場所で流す。

## 警報

- `ForbiddenByObjectOrUndeclared`：出どころが `object`（返すオブジェクトとフィールドの規則の拒否。scope と規則の食い違い）か `undeclared`（宣言の無い型・リゾルバ・mutation の拒否）の `FORBIDDEN` が増えた（`../slo.md`「状態の警報」）
- 利用者からの「他社のデータが見えた」という問い合わせ

## 確かめること

1. どの出どころの `FORBIDDEN` が、どの操作で増えたかを、Web の exporter から読む。`object` はテナントの境界の不具合の兆しで、`undeclared` は宣言を忘れた入口が本番に出た兆しである。

   ```sh
   curl -s localhost:9394/metrics | grep -E '^graphql_top_level_errors_total\{.*code="FORBIDDEN"'
   ```

2. アプリの接続が、アプリのロールで張られているかを確かめる。所有ロール（表の所有者で `BYPASSRLS`）か、ほかのロールの接続がアプリから来ていれば、RLS が効いていない。

   ```sh
   echo "SELECT usename, application_name, count(*) FROM pg_stat_activity WHERE datname = current_database() GROUP BY 1, 2;" | bin/rails dbconsole -p
   ```

3. アプリのロールの属性を確かめる。`rolsuper` と `rolbypassrls` はどちらも `f` でなければならない。どちらかが `t` なら、RLS はそのロールに効かない。

   ```sh
   echo "SELECT rolname, rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user;" | bin/rails dbconsole -p
   ```

4. RLS を強制する表（`FORCE ROW LEVEL SECURITY`）とポリシーの名前を、`db/structure.sql` と比べる。差が出なければ、表とポリシーの組は揃っている。

   ```sh
   bin/rails runner 'puts ActiveRecord::Base.connection.select_values("SELECT relname FROM pg_class WHERE relnamespace = current_schema()::regnamespace AND relforcerowsecurity")' | LC_ALL=C sort > tmp/rls_forced_live.txt
   grep -oE '^ALTER TABLE ONLY public\.[a-z0-9_]+ FORCE ROW LEVEL SECURITY' db/structure.sql | awk '{sub(/^public\./, "", $4); print $4}' | LC_ALL=C sort > tmp/rls_forced_expected.txt
   diff tmp/rls_forced_expected.txt tmp/rls_forced_live.txt

   bin/rails runner 'ActiveRecord::Base.connection.select_rows("SELECT tablename, policyname FROM pg_policies WHERE schemaname = current_schema()").each { puts _1.join(" ") }' | LC_ALL=C sort > tmp/rls_policies_live.txt
   grep -oE '^CREATE POLICY [a-z0-9_]+ ON public\.[a-z0-9_]+' db/structure.sql | awk '{sub(/^public\./, "", $5); print $5, $3}' | LC_ALL=C sort > tmp/rls_policies_expected.txt
   diff tmp/rls_policies_expected.txt tmp/rls_policies_live.txt
   ```

   名前が揃っていても、式が書き換わっていることがある。疑いが残るなら、`pg_policies` の `qual` と `with_check` を、`structure.sql` の `CREATE POLICY` の行と見比べる。

5. 1〜4 のどれにも差が無ければ、DB の守りは崩れていない。`object` の `FORBIDDEN` は、公開 API の scope と、返す型の規則が食い違った入口で起きている。操作の終わりのイベント（`graphql.operation_completed`）の `forbidden_reasons` と `context` の `graphql_operation` から、入口を特定する。本番はログの基盤で、開発の環境では次で引く。

   ```sh
   grep '"forbidden_reasons":\[[^]]*"\(object\|undeclared\)"' log/events.log | tail -20
   ```

## 止血

疑いが消えるまで、メンテナンスの切り替えで業務の入口を止める（`../guides/config.md`「メンテナンスの切り替え」）。

1. Web のプロセスに環境変数 `MAINTENANCE_MODE=1` を設定して起動し直す。GraphQL（`POST /graphql`）とファイルの受け口（`POST /imports/files`）が、何も実行せずに 503 を返す。ログインと SendGrid の Webhook は止まらない。Webhook は受信の表に書くだけで、止めると配信結果を失うからである。
2. ワーカーは切り替えで止まらないので、`bin/jobs` も止める。イベントの受け手と取り込みは、業務の表を書き続ける。止めている間に溜まったジョブは、再開した後に流れる。
3. 止まったことを確かめる。

   ```sh
   curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:3000/graphql -H 'Content-Type: application/json' -d '{}'   # 503
   ```

## 復旧

- **ロールか接続の誤り**（確かめることの 2・3）：アプリの環境変数の DB の資格情報を、アプリのロールのものに戻して起動し直す。所有ロールの資格情報は、マイグレーションの工程にだけ渡す（`../architecture/data-model.md`「RLS」）。ロールの属性は、所有ロールで `ALTER ROLE <アプリのロール> NOSUPERUSER NOBYPASSRLS` で戻す。
- **表かポリシーの誤り**（確かめることの 4）：`structure.sql` と違う状態を、マイグレーションで `structure.sql` の形に戻す。手で `ALTER TABLE` や `CREATE POLICY` を流さない。流すと、次のマイグレーションの後の `structure.sql` に混ざる。
- **入口の誤り**（確かめることの 5）：入口の公開 API の scope か型の規則を直してデプロイし、入口の行列（`spec/matrix/graphql_matrix_spec.rb`）にその入口の行があるかを確かめる。

直したら `MAINTENANCE_MODE` を外して Web を起動し直し、`bin/jobs` を起動する。

## 事後にすること

- 影響を受けたテナントを洗い出す。`graphql.operation_completed` のイベントの `context` の `tenant_id` と `correlation_id` で、疑いのあった時間の要求を引き、同じ相関 ID のイベントで、その要求がどの行を書いたかをたどる。相手テナントに効果が及ぶ書き込みは監査ログにも残る（`../architecture/data-model.md`「監査ログ（`platform`）」）
- 影響を受けたテナントに知らせる
- 誤りが入った経路（手で流した SQL・デプロイの設定・入口の宣言）を障害の記録に残し、同じ経路を止める検査を足す
