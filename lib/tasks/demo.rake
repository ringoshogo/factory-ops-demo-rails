# 公開の配置の毎日の作り直し（lib/demo_reset.rb）。CronJob の daily-reset が、DEMO_WORLD_ENABLED=1 と所有ロールの資格情報を渡して流す
namespace :demo do
  desc "公開の配置の DB を作り直し、シードの世界を作る。web と jobs を止めてから作り、最後に 1 に戻す"
  task reset: :environment do
    DemoReset.run
  rescue DemoReset::Refused => error
    abort "demo:reset: #{error.message}"
  end
end
