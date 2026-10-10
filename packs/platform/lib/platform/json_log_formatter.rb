require "json"
require "logger"
require "time"

module Platform
  # Rails.logger の 1 行を 1 件の JSON にする（docs/guides/config.md「ログ」）。
  # 要求 ID やテナントは、タグではなく Rails.event の文脈から context に入れる
  class JsonLogFormatter < ::Logger::Formatter
    def call(severity, time, progname, message)
      line = { time: time.utc.iso8601(6), level: severity, progname:, message: text(message),
        context: ActiveSupport.event_reporter.context }
      "#{line.compact.to_json}\n"
    end

    private

    # 例外のメッセージは DB のエラーの詳細などに入力の値を含むので、クラス名だけを書く
    def text(message)
      case message
      when String then message
      when Exception then message.class.name
      else message.inspect
      end
    end
  end
end
