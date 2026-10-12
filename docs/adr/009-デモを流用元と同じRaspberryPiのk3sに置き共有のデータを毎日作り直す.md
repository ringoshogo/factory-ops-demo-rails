# 009. デモを流用元と同じ Raspberry Pi の k3s に置き、共有のデータを毎日作り直す

## ステータス

承認（作者の判断 OI-14、2026-10-12）。実装は `../implementation-plan.md` M41 で行う。Rails・ジョブのワーカー・Next・PostgreSQL を流用元のデモと同じ Raspberry Pi の k3s に置き、画面だけを Cloudflare Tunnel で公開し、全員が使う 1 つのデモのデータを毎日 Web とワーカーを止めて DB ごと作り直す。

裏返る条件：実機で測ったメモリが、流用元のデモと同居できる量に収まらない → 常に動くコンテナを減らす（ワーカーを Web の Puma の中で動かす）か、配置先を分ける。

## コンテキスト

### 決めること

M33 までで、デモは手元（`bin/rails server` と `next start`）で動く。作者は、流用元と同じく Raspberry Pi の k3s に置いてインターネットに公開すると決めた（OI-14）。訪問者ごとのデータの分離は作らず、全員が同じデモのデータを使い、毎日決まった時刻にシードから作り直す。

そこで、次の 6 つを決める。どこまでを外に出すか、何を誰に渡すか、どう作り直すか、どのイメージで動かすかである。

### 本デモの事情

- 流用元のデモは、同じ Raspberry Pi の k3s の名前空間 `factory-ops` で、Go の API と PostgreSQL を動かしている（流用元の `deploy/`）。画面は Cloudflare Workers にあり、k3s には無い。Secret はリポジトリに置かず、作者が手で入れる。
- 本デモは常に 4 つのプロセスを動かす：Rails の Web、Solid Queue のワーカー、Next のサーバー、PostgreSQL。Rails と Next はどちらもインタプリタのプロセスで、流用元の Go の API よりメモリを使う。
- Rails は、DB に 2 つのロールで接続する。所有ロールは RLS を素通りするので、資格情報をマイグレーションの工程にだけ渡し、Web とワーカーに渡さない（`../architecture/data-model.md`「RLS」、`config/database.yml`）。
- シードの世界を作る `DemoWorld` と、テナントを作る `Partnerships::Onboarding` は、本番の環境で例外にしている（OI-140・OI-141）。デモの準備の書き込みが、本物の本番に流れないようにするためである。
- `DemoWorld` は、イベントと取り込みのジョブを claim せずにその場で流す。同じ間に `bin/jobs` が動くと、同じジョブを両方が流しうる（OI-143）。
- 監査ログは追記だけの表で、所有ロールでも行を消せず、`TRUNCATE` もトリガーが止める（`../architecture/data-model.md`「監査ログ（`platform`）」）。
- 本番の環境の通知の送り先は SendGrid である。シードのアカウントのメールアドレスは実在しない。
- 流用元は、Raspberry Pi を夜に止める運用にしたので、毎日のリセットの CronJob を一度も動かしていない（流用元の `deploy/daily-reset-cronjob.yaml` と台帳の D-1）。

## 決定

1. **共有の 1 つのデータを毎日作り直す。** 訪問者ごとのデータの分離（流用元の「デモを開始」）は作らない。作者の判断（OI-14）である。訪問者の書き込みは、次の作り直しまで全員に見える。訪問者に許す操作は OI-148 で作者が決める。
2. **画面だけを公開し、Rails は公開しない。** Ingress は Next の `frontend` だけに置き、Rails の `web` は `ClusterIP` の Service だけにする。画面は Rails を Next のサーバーから呼び（M33「Rails をどこから呼ぶか」）、ブラウザが Rails を直接呼ぶ取り込みのファイルの送信も、Next の `rewrites` で同じオリジンの下に出す。Rails を外から呼べないので、GraphQL の入口を外に晒さず、CORS も開けない。
3. **作り直しは、Web とワーカーを 0 にしてから DB ごと作り直す。** CronJob が `bin/rails demo:reset` を流し、Kubernetes の API で `web` と `jobs` の Deployment を 0 にして Pod が消えるのを待ち、所有ロールで DB を消して作り直し、`DemoWorld` で世界を作り、成功しても失敗しても 1 に戻す。DB の接続が残らず、シードがその場で流すジョブを `bin/jobs` が同時に流さない。監査ログの行は消さず、DB ごと作り直すので、追記だけの保証は変えない。作り直しの数分は、画面が「API に届かない」の表示になる。
4. **本番の環境でデモの世界を作るのは、`DEMO_WORLD_ENABLED=1` を渡したプロセスだけにする。** 配置は本番の環境（`RAILS_ENV=production`）で動かし、作り直しの CronJob にだけこの変数を渡す。所有ロールの資格情報を作り直しとマイグレーションの工程にだけ渡すのと同じ形である。Web とワーカーは、この変数を持たないので、いまと同じく `DemoWorld` と `Partnerships::Onboarding` を呼べない。
5. **ワーカーは Solid Queue の async のモードで、1 つのプロセスにする。** キューごとのワーカーの分け方（`007` 決定 7）はそのままにし、ワーカーをプロセスではなくスレッドにする。fork のモードでは、スーパーバイザ・ワーカー 4 つ・ディスパッチャ・スケジューラの 7 プロセスがそれぞれ Rails を抱え、同居する Raspberry Pi のメモリを圧迫する。
6. **イメージは、GitHub ホストのランナーで QEMU と buildx を使い、`linux/arm64` で作る。** タグは git の SHA に固定し、GHCR に置く。リポジトリが private の間はパッケージも private なので、流用元と同じく読み取りの Secret で取りに行く。流用元は Go をクロスコンパイルして `RUN` の無い Dockerfile で済ませたが、Rails と Next はイメージの中で依存を入れて組み立てるので、その手は使えない。

メールは外へ送らない。公開の配置では、通知の送り先を `NOTIFICATIONS_PROVIDER=file_system` でファイルに替える。ホスト名・作り直しの時刻・Raspberry Pi の機種とメモリは、作者が決める（OI-145〜OI-147）。

## 結果

### 得られるもの

- **作者が既に持つ Raspberry Pi と Cloudflare Tunnel だけで公開できる。** 新しい費用もアカウントも要らない。
- **公開の面が画面の 1 つだけになる。** Rails の GraphQL とファイルの受け口は、クラスタの外から届かない。
- **作り直しの間に、データを書く者が作り直しのほかにいない。** 消す DB に接続が残らず、ジョブを二重に流さない。

### 引き受けるコスト

- **訪問者の書き込みが全員に見える。** 取引関係を失効させた訪問者がいれば、次の作り直しまで、ほかの訪問者も失効した後の画面を見る。
- **作り直しの数分は、画面が API に届かない。** 時刻は利用の少ない時間に置く（OI-146）。
- **async のモードは、Solid Queue が既定にしていない形である。** 重い取り込みが CPU と GVL をイベントの配送と分け合う。キューごとのワーカーは分かれたままなので、取り込みがイベントのキューを待たせることはない。
- **QEMU の上の組み立ては遅い。** Rails のイメージは、ネイティブの拡張を持つ gem を arm64 で組み立てる。
- **流用元のデモと資源を分け合う。** 見積もり（M41 の作るもの 6）は実機で測っていない。

### 撤退コスト

小さい。`deploy/` と CI の `images` のジョブと `demo:reset` を消せば、手元で動かす形に戻る。業務の表・RLS・policy は変えていない。

### 見直す条件

- 実機で測ったメモリが同居できる量に収まらない → ワーカーを Web の Puma の中で動かす（Solid Queue の Puma のプラグイン）か、配置先を分ける。
- 訪問者の書き込みでデモが壊れる日が続く → 壊す操作を公開の配置で止めるか、訪問者ごとのデータの分離（流用元の形）を作る。
- `images` のジョブが 20 分を超える → arm64 の GitHub ホストのランナーに移す。リポジトリが private の間に使えるかは、移すときに GitHub の文書で確かめる。
- async のモードで、取り込みの間にイベントの配送の遅れの警報（`../slo.md`）の閾値を超える → fork のモードに戻し、メモリの見積もりを直す。

## 代替案

### A. 作り直しを、動いている DB の表を空にして行う（`TRUNCATE`）

不採用。監査ログの `TRUNCATE` はトリガーが止める。止めるにはトリガーを外すことになり、追記だけの保証（M19）を作り直しの工程が破る。Web とワーカーを止めないので、シードがその場で流すジョブを `bin/jobs` が同時に流す（OI-143）。

### B. Web とワーカーを止めずに、接続を切って DB を消す（`DROP DATABASE ... WITH (FORCE)`）

不採用。所有ロールに、他のロールの接続を切る権限（`pg_signal_backend`）を与えることになる。切られた Web とワーカーは作り直しの間に再接続を試み、ワーカーは作り直しの途中の DB でジョブを拾いうる。

### C. デモ用の Rails の環境（`RAILS_ENV=demo`）を足す

不採用。`DemoWorld` の本番の例外を変えずに済むが、`config/database.yml`・`config/queue.yml`・`config/recurring.yml` と、本番の環境で決めている振る舞い（宣言漏れの `FORBIDDEN` など）に、もう 1 つの環境の行を足すことになる。本番の環境とずれた環境で公開すると、本番の設定を確かめたことにならない。

### D. 画面を流用元と同じく Cloudflare Workers に置く

不採用。作者の判断（OI-14）で、画面も同じ k3s に置く。Workers に置くと、Rails を外に公開し、画面からの呼び出しを鍵で守る形（流用元の `X-Demo-Proxy-Key`）が要る。

### E. ワーカーを fork のモードのまま動かす

既定にしない。Solid Queue の既定で、ワーカーごとにプロセスが分かれるが、メモリの見積もりが Raspberry Pi の同居に収まらない見込みである。実機で測って収まるなら、見直す条件に従って戻す。

## 確認した事項

- Solid Queue 1.7.0 の README「Fork vs. async mode」：`bin/jobs --mode async` か `SOLID_QUEUE_SUPERVISOR_MODE=async` で、ワーカー・ディスパッチャ・スケジューラをスーパーバイザと同じプロセスのスレッドで動かす。async のモードでは `processes` の設定を無視する。
- 流用元（`958de71`）の `deploy/`：名前空間 `factory-ops`、Traefik の Ingress、`local-path` の PVC、Secret を手で入れる運用、`ghcr-pull-secret`、`timeZone: Asia/Tokyo` と `concurrencyPolicy: Forbid` の CronJob。
