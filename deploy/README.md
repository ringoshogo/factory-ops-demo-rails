# deploy：公開の配置

作者がデモを、流用元 factory-ops-demo と同じ Raspberry Pi の k3s に置き、画面を Cloudflare Tunnel で公開するときに読む。決めたことと比べた案は `docs/adr/009-デモを流用元と同じRaspberryPiのk3sに置き共有のデータを毎日作り直す.md` にある。

配置は次の流れで動く。

```
CI（main への push） 2 つのイメージを arm64 で作り、GHCR に git の SHA のタグで置く
作者                 名前空間と Secret を作り、マニフェストを適用する
migrate の Job       所有ロールで業務の DB を作り、マイグレーションを流す
web・jobs・frontend  Rails・Solid Queue のワーカー・Next が動く。外へは frontend だけが Traefik の Ingress で出る
daily-reset          毎日、web と jobs を 0 にして DB ごと作り直し、シードの世界を作って 1 に戻す
```

リポジトリが確かめるのは、マニフェストの規則（`spec/platform/deploy_manifests_spec.rb`）、作り直しの順（`spec/platform/demo_reset_spec.rb`）、イメージが組み立てられて本番の環境を読み込めること（CI の `images` のジョブ）と、テストの通った main の commit のイメージだけが GHCR に置かれること（CI の `publish` のジョブ）までである。メモリ・CronJob の時刻・Tunnel は実機でしか確かめられないので、作者が「作者の手順」で確かめる。作者が結果を PR か台帳に書くまで、公開しない。

## 置くもの

マニフェストは Kustomize の 1 つの `kustomization.yaml` に並べ、名前空間 `factory-ops-rails` に置く。

| ファイル | 置くもの | 外から届くか |
|---|---|---|
| `postgres.yaml` | PostgreSQL 18 の Deployment・Service・PVC `postgres-data`・初期化のスクリプト | 届かない |
| `migrate-job.yaml` | `bin/rails db:prepare db:grant_app_role` を流す Job | — |
| `web.yaml` | Rails の `bin/rails server` の Deployment・Service | 届かない。Next のサーバーだけが呼ぶ |
| `jobs.yaml` | `bin/jobs`（async のモード）の Deployment | — |
| `frontend.yaml` | Next の standalone のサーバーの Deployment・Service・Ingress | 届く。公開のホスト名で Traefik が受ける |
| `daily-reset.yaml` | 毎日の作り直しの CronJob と、その ServiceAccount・Role・RoleBinding | — |

## 作者が決める値

作者は 2026-10-13 に、次の値をどれも既定のままと決めた（OI-145〜OI-149）。値を変えるときは、次の場所で差し替える。

| 値 | 既定 | 差し替える場所 | 台帳 |
|---|---|---|---|
| 公開の画面のホスト名 | `factory-ops-rails.hayatec.dev` | `kustomization.yaml` の `public-site` の `host`。Ingress の `host` と `web` の `FRONTEND_ORIGIN` に写る | OI-145 |
| 毎日の作り直しの時刻と、止めていた後に流す猶予 | 日本時間の 4:30、6 時間 | `daily-reset.yaml` の `schedule` と `startingDeadlineSeconds` | OI-146 |
| 各コンテナの requests と limits | 実機で測っていない見積もり（Raspberry Pi 4 Model B の 8GB、総量 7.6Gi、スワップ無しに収まる） | 各マニフェストの `resources`。測った値で直したら `docs/adr/009` の「確認した事項」にも書く | OI-147 |
| 訪問者に許す操作 | すべて許し、毎日の作り直しで戻す | 止めることにしたら、止め方を計画に起こす | OI-148 |
| 共有のアカウントのログアウト | セッションの世代を進めない | `web.yaml` の `SHARED_DEMO_ACCOUNTS`。消すと、ログアウトが同じアカウントのほかの訪問者を切る | OI-149 |

## Secret

Secret はリポジトリに置かない。作者が「作者の手順」1 で名前空間に入れ、値はその場で生成して、どこにも書き残さない。マニフェストが参照する Secret とキーは次のとおりで、`deploy/preflight.sh` がマニフェストから同じ一覧を集めて、名前空間にあるかを確かめる。

| Secret | キー | 使うワークロード | 中身 |
|---|---|---|---|
| `db-credentials` | `app-password` | postgres・web・jobs・migrate・daily-reset | アプリのロール `factory_app` のパスワード |
| `db-credentials` | `owner-password` | postgres・migrate・daily-reset | 所有ロール `factory_owner` のパスワード。RLS を素通りするので、DB を作る工程にだけ渡す |
| `db-credentials` | `superuser-password` | postgres | PostgreSQL の `postgres` のパスワード。Rails は使わない |
| `ghcr-pull-secret` | `.dockerconfigjson` | web・jobs・frontend・migrate・daily-reset | GHCR のイメージを取る読み取りの資格情報。パッケージの可視性はリポジトリと別に決まるので、private でも取れるように置く |
| `rails-credentials` | `secret-key-base` | web・jobs・migrate・daily-reset | セッションの Cookie の暗号化の鍵。`config/credentials.yml.enc` は使わない |

`owner-password` と `app-password` は、postgres の PVC が空の初回の起動でだけロールに入る。初回の後に Secret を変えても、ロールのパスワードは変わらない。

## 作者の手順

作者は、次の 1〜6 をこの順に行う。コマンドは手元の Mac から `ssh raspi` で Raspberry Pi の `kubectl` を呼ぶ形で書く（流用元と同じ）。`<SHA>` は、CI の `publish` のジョブが GHCR に置いた main の commit の SHA である。

### 1. 名前空間と Secret を作る

作者は、Raspberry Pi の上でパスワードと鍵を生成し、そのまま Secret にする。値はどのコマンドの引数にも入れない。引数はプロセスの一覧から読めるからである。値はシェルの組み込みのヒアドキュメントと標準入力で `kubectl create -f -` に渡し、手元に持ち帰らない。

```sh
ssh raspi kubectl create namespace factory-ops-rails
ssh raspi bash -s <<'EOF'
set -eu
kubectl create -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: factory-ops-rails
type: Opaque
stringData:
  superuser-password: $(openssl rand -hex 24)
  owner-password: $(openssl rand -hex 24)
  app-password: $(openssl rand -hex 24)
YAML
kubectl create -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: rails-credentials
  namespace: factory-ops-rails
type: Opaque
stringData:
  secret-key-base: $(openssl rand -hex 64)
YAML
EOF
```

GHCR の読み取りの Secret は、流用元の `ghcr-pull-secret` と同じく、`read:packages` だけを持つ期限付きの classic PAT で作る。作者は手元の端末で PAT を画面に出さずに読み、組み込みの `printf` で Secret の JSON を組み立てて、ssh の標準入力で Raspberry Pi の `kubectl` に渡す。

```sh
printf 'GHCR の PAT: '; read -rs PAT; echo
auth=$(printf '%s' "ringoshogo:$PAT" | base64 | tr -d '\n')
printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"ghcr-pull-secret","namespace":"factory-ops-rails"},"type":"kubernetes.io/dockerconfigjson","stringData":{".dockerconfigjson":"{\\"auths\\":{\\"ghcr.io\\":{\\"auth\\":\\"%s\\"}}}"}}\n' "$auth" \
  | ssh raspi kubectl create -f -
unset PAT auth
```

### 2. 適用

作者は、Secret がそろったことを確かめてから、タグを `<SHA>` にしたマニフェストを適用する。CI は 2 つのイメージ（`api` と `frontend`）を続けて push するので、片方だけが置かれることがある。作者は、同じ `<SHA>` の 2 つのイメージが GHCR にあることも確かめる。タグはファイルに書かず、描いた結果だけを差し替える。

```sh
KUBECTL="ssh raspi kubectl" deploy/preflight.sh
kubectl kustomize deploy | sed "s/REPLACE_WITH_GIT_SHA/<SHA>/" | ssh raspi kubectl apply -f -
ssh raspi kubectl wait -n factory-ops-rails --for=condition=complete job/migrate --timeout=10m
ssh raspi kubectl rollout status -n factory-ops-rails deployment/web --timeout=10m
```

一覧のために別のコンテキストへ値を写す表か列（在庫の品目の写し、出荷依頼の受注番号の写し）を足すマイグレーションは、写しを埋めない（`docs/adr/011-在庫の一覧のために品目のコードと名前を同期で写す.md`）。次の毎日の作り直しがシードで写しを作るまで、在庫の画面の品目のコードと名前での並べ替えと検索が当たらず、受注番号で並べた出荷依頼の画面では、写しの空の出荷依頼が末尾に並ぶ。作者は、待たずに埋めるときだけ、適用の後に `ssh raspi kubectl exec -n factory-ops-rails deployment/web -- bin/rails read_models:rebuild` を流す。アプリのロールで動き、テナントごとに、品目の写しを足した数と書き直した数と、出荷依頼の受注番号を書き直した数を出す。

`migrate` の Job は spec を変えられないので、2 回目からの適用では、適用の前に `ssh raspi kubectl delete job migrate -n factory-ops-rails --ignore-not-found` で消す。消さずに適用すると `field is immutable` で失敗する。`jobs` は、初回の適用で `migrate` が表を作り終えるまで、起動に失敗して再起動を繰り返す。

`kubectl wait` が時間切れになったら、`migrate` は再試行（`backoffLimit: 3`）を使い切って `Failed` で止まっている。初回の適用で postgres の起動が遅れたときに起きる。作者は `ssh raspi kubectl logs -n factory-ops-rails job/migrate` で原因を見てから、Job を消して同じ適用を流し直す。

`web`・`jobs`・`frontend` は新旧の Pod を同時に置かない（`Recreate`。Raspberry Pi のメモリに 1 プロセス分を上乗せしないため）ので、適用のたびに、古い Pod が止まってから新しい Pod が応えるまで画面が止まる。`web` は起動に最大 3 分待つ。作者は、訪問者の少ない時間に適用する。

適用は、毎日の作り直しの時刻（日本時間の 4:30 から数分）を避ける。適用はマニフェストの `replicas: 1` で、作り直しが 0 にした `web` と `jobs` を途中で起こすからである。

### 3. 作り直しを手で 1 回流す

初回の適用の後の DB は空なので、作者は作り直しを手で 1 回流し、シードの世界を作る。

```sh
ssh raspi kubectl create job -n factory-ops-rails --from=cronjob/daily-reset manual-reset-1
ssh raspi kubectl wait -n factory-ops-rails --for=condition=ready pod -l job-name=manual-reset-1 --timeout=10m
ssh raspi kubectl logs -n factory-ops-rails -f job/manual-reset-1
ssh raspi kubectl get deployment -n factory-ops-rails web jobs
```

`logs -f` の前の `wait` は、イメージを取り終えて Pod が動き出すのを待つ。動き出す前の `logs` は失敗する。ログの末尾にシードのアカウントの一覧が出て、`web` と `jobs` の `READY` が `1/1` に戻れば終わりである。CronJob の `timeZone` と `startingDeadlineSeconds` が効くかは、Raspberry Pi を作り直しの時刻をまたいで止めた日に、起動の後に `ssh raspi kubectl get jobs -n factory-ops-rails -l app=daily-reset` で 1 回見る。

### 4. メモリを測る

作者は、k3s に同梱の metrics-server で、両方の名前空間の Pod のメモリを測る。作り直しの間（手順 3 の Job が動いている間）の最大も見る。

```sh
ssh raspi kubectl top pods -n factory-ops-rails
ssh raspi kubectl top pods -n factory-ops
ssh raspi free -h
```

測った値で各マニフェストの `resources` を直す PR を作る（「作者が決める値」）。あわせて、画面で 5 万行の CSV の取り込みを流しながら発注を登録し、受注が確定するまでの時間を測る。async のモードで分かるほど遅れれば、`docs/adr/009` の「見直す条件」に当たる。Raspberry Pi にはスワップが無く、データは SD カードに載るので、取り込みの後に `ssh raspi kubectl get pods -n factory-ops-rails` の `RESTARTS` が増えていないこと（limits を超えた OOM とプローブの時間切れが起きていないこと）も見る。

### 5. Cloudflare Tunnel に公開のホスト名を足す

作者は、流用元の tunnel の設定（リポジトリの外にある）に、公開のホスト名を k3s の Traefik へ送る公開のホスト名を足す。流用元のホストに掛けたレート制限と Bot Fight Mode を、このホスト名にも掛ける。

### 6. 公開の URL で確かめる

作者は、公開の URL で次を確かめる。

- ログインの画面のシードのアカウントでログインし、受注一覧と発注一覧が出る
- Rails の Service（`web`）に、クラスタの外から届かない
- 流用元のデモがこれまでどおり動く

## 動かしている間

### 作り直しが途中で止まったとき

作り直しは、成功しても失敗しても `web` と `jobs` を 1 に戻す。ただし、作り直しの Pod がメモリの上限で殺されたときと、Raspberry Pi が止まったときは戻せない。画面が「API に届かない」のままなら、作者は次で戻す。次の日の作り直しも、最後に 1 に戻す。

```sh
ssh raspi kubectl scale deployment -n factory-ops-rails web jobs --replicas=1
```

作り直しは、止められたとき（`activeDeadlineSeconds` を過ぎたときと、Job を消したとき）も、SIGTERM の後の猶予（`terminationGracePeriodSeconds`）の間に 1 に戻す。DB のタスクの途中で止められたときは、作りかけの DB に向けて `web` と `jobs` が起きるので、作者は手順 3 と同じく手で流し直す。

作り直しは再試行しない（`backoffLimit: 0`）。途中で失敗した作り直しを繰り返して、DB を何度も消さないためである。失敗した日は、手順 3 と同じく手で流し直すか、次の日の作り直しを待つ。手で流した作り直しが定時の作り直しと重なっても、後から始めた方は、DB のアドバイザリロックを取れずに何もせずに止まる。CronJob の `concurrencyPolicy: Forbid` は、手で作った Job を止めないからである。

### 作り直しが飛ばされた日

Raspberry Pi を作り直しの時刻（日本時間の 4:30）に止めていて、時刻から 6 時間（`startingDeadlineSeconds`）を過ぎて起動した日は、その日の作り直しが飛ばされる。データは前の日のまま残り、次の日の時刻に作り直される。前の日の訪問者の書き込みを残したくなければ、作者は手順 3 と同じく手で流す。Job の名前は日ごとに変える。

```sh
ssh raspi kubectl create job -n factory-ops-rails --from=cronjob/daily-reset manual-reset-$(date +%Y%m%d)
```

飛ばされたかは、`ssh raspi kubectl get jobs -n factory-ops-rails -l app=daily-reset` にその日の Job が無いことで分かる。

### PostgreSQL のイメージを上げたとき

作者は、`postgres.yaml` のイメージのタグを上げて適用したら、名前の列の照合順序 `ja-x-icu` の版を確かめる（`docs/guides/config.md`「照合順序の版」）。毎日の作り直しは、新しい DB に `template1` の版の記録を写すので、作り直しでは古い記録が改まらない。

```sh
ssh raspi kubectl exec -n factory-ops-rails deployment/postgres -- psql -U postgres -d template1 -Atc "SELECT collversion, pg_collation_actual_version(oid) FROM pg_collation WHERE collname = 'ja-x-icu'"
```

2 つの版が等しければ何もしない。違えば、`template1` の記録を改めてから、手順 3 と同じく作り直しを手で流す。作り直しが業務の DB を消して作り、改めた記録を写し、索引を新しい ICU で作る。

```sh
ssh raspi kubectl exec -n factory-ops-rails deployment/postgres -- psql -U postgres -d template1 -c 'ALTER COLLATION pg_catalog."ja-x-icu" REFRESH VERSION'
ssh raspi kubectl create job -n factory-ops-rails --from=cronjob/daily-reset manual-reset-$(date +%Y%m%d)
```

### 送らないメール

公開の配置のアカウントのメールアドレスは実在しないので、通知のメールは外へ送らず、`web`・`jobs`・`daily-reset` の Pod の `/rails/tmp/mails` にファイルで書く（`NOTIFICATIONS_PROVIDER=file_system`）。置き場は Pod と一緒に消える。
