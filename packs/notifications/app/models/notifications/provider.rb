module Notifications
  # メールの送信先（docs/adr/007 決定 5 の A-2）。config.x.notifications.provider で、本番は SendGrid、開発はファイル、
  # テストはメモリに切り替える。どの実装も deliver(message) で受け付けを返すか、下の 3 つの例外で失敗を分ける
  module Provider
    Message = Data.define(:from, :to, :subject, :body, :custom_args)
    Accepted = Data.define(:message_id)

    class Error < StandardError; end
    # 5xx・タイムアウト・接続の失敗。間隔を延ばしながら再試行する
    class TransientError < Error; end
    # 429。wait は応答が示した待ち時間（秒）で、示さなければ nil
    class RateLimited < Error
      attr_reader :wait

      def initialize(message = "rate_limited", wait: nil)
        super(message)
        @wait = wait
      end
    end
    # 再試行しても結果が変わらない失敗（400・401・403・413 など）。メッセージは失敗の理由として送信記録に書く
    class PermanentError < Error; end

    def self.current
      @current ||= build(Rails.configuration.x.notifications)
    end

    # 設定を読み直す。テストで提供元を差し替えた後に呼ぶ
    def self.reset!
      @current = nil
    end

    def self.build(config)
      case config.provider
      when :sendgrid
        Sendgrid.new(api_key: config.sendgrid_api_key, sandbox: config.sendgrid_sandbox, production: Rails.env.production?)
      when :file_system then FileSystem.new(Rails.root.join("tmp/mails"))
      when :fake then FakeProvider
      else raise ArgumentError, "config.x.notifications.provider が不明: #{config.provider.inspect}"
      end
    end
  end
end
