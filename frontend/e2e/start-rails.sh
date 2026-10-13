#!/bin/sh
# E2E の Rails を起こす。Playwright の webServer が呼ぶ。
#
# 1. E2E の DB を作り直し、世界を作る (bin/rails e2e:check・db:drop・db:prepare・e2e:prepare)。DemoWorld はジョブを
#    その場で流すので、bin/jobs はまだ起こさない
# 2. 準備を終えてから bin/jobs を起こす。イベントで進む表示 (発注から受注の確定) をワーカーが流す
# 3. Rails のサーバーを起こす。Playwright は /up が答えてから次の webServer とテストに進む
#
# Playwright は webServer を globalSetup より先に起こすので、準備を globalSetup に置くと bin/jobs が先に動く。
# 順はこのスクリプトの並びだけで決め、e2e:prepare は作る前と後に Solid Queue のプロセスが無いことを確かめる。
# Playwright は終わるときに webServer のプロセスのグループごとシグナルを送る (playwright 1.64 の types/test.d.ts の
# TestConfigWebServer.gracefulShutdown の説明) ので、裏で起こした bin/jobs も一緒に止まる。
set -eu
cd "$(dirname "$0")/../.."

export RAILS_ENV=test
bin/rails e2e:check
bin/rails db:drop db:prepare
bin/rails "e2e:prepare[${E2E_WORKERS:-1}]"
bin/jobs &
exec bin/rails server -p "${E2E_RAILS_PORT:-3200}" -b 127.0.0.1
