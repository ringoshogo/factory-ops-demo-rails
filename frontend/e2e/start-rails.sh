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
# CI と同じく、起動の時にアプリを読み込んでから /up に答える (config/environments/test.rb)。CI そのものは渡さない。
# CI は「CI の上で動いている」ことを表し、読み込みのほかにも gem や道具が見て振る舞いを変えうるので、読み込みだけを切り替える
export E2E_EAGER_LOAD=1
bin/rails e2e:check
bin/rails db:drop db:prepare
bin/rails "e2e:prepare[${E2E_WORKERS:-1}]"
bin/jobs &
exec bin/rails server -p "${E2E_RAILS_PORT:-3200}" -b 127.0.0.1
