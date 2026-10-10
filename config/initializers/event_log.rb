require_relative "../../packs/platform/lib/platform/json_log_subscriber"

# Rails.event をログの出口にする。本番は標準出力に、開発とテストは log/events.log に、1 件を 1 行の JSON で書く
# （docs/guides/config.md「ログ」）
io = Rails.env.production? ? $stdout : File.open(Rails.root.join("log/events.log"), "a").tap { _1.sync = true }
Rails.event.subscribe(Platform::JsonLogSubscriber.new(io))
