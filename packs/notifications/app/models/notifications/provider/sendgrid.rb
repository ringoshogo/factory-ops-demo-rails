require "net/http"

module Notifications
  module Provider
    # SendGrid の v3 の送信 API（docs/adr/007 決定 5 の A-2）。応答と例外を、受け付け・再試行・再試行しない失敗に分ける
    class Sendgrid
      ENDPOINT = URI("https://api.sendgrid.com/v3/mail/send")

      # Net::HTTP の既定の時間切れはどれも 60 秒で、external_mail の 2 本のスレッドを長く塞ぐ
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      WRITE_TIMEOUT = 10

      # タイムアウトと接続の失敗。相手に届いたかが分からないが、重複を受け入れる（docs/adr/007 決定 6 の C-2）ので再試行する。
      # 並べ漏れた例外はジョブから上がり、テナントのトランザクションが戻って送信記録が待機中のまま残るので、
      # TLS・ソケット（SystemCallError は Errno::* をまとめる）・応答の読み取りの失敗も含める
      CONNECTION_ERRORS = [
        Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, SystemCallError, IOError,
        OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError
      ].freeze

      # 待ち時間の上限。これより長く待たせる応答でも、1 時間後にもう一度試す
      MAX_RATE_LIMIT_WAIT = 3600

      class SandboxRequired < StandardError; end

      # 本番以外で sandbox mode を外すと、開発やテストの送信が本物の宛先に届く。設定を読んだ時点（起動時）で止める
      def initialize(api_key:, sandbox:, production:)
        raise SandboxRequired, "本番以外の環境では config.x.notifications.sendgrid_sandbox を true にする" unless sandbox || production

        @api_key = api_key
        @sandbox = sandbox
      end

      # 応答の種類を、メトリクスの経路が数えるイベントに出す。接続の失敗は相手に届いたかが分からないので timeout にまとめる
      def deliver(message)
        raise PermanentError, "missing_api_key" if @api_key.blank?

        response = post(body(message))
        responded(status_class(response.code.to_i))
        classify(response)
      rescue *CONNECTION_ERRORS => error
        responded("timeout")
        raise TransientError, error.class.name
      end

      # API キーを inspect とログに出さない
      def inspect = "#<#{self.class.name} sandbox=#{@sandbox}>"

      private

      # 宛先ごとに personalization を分け、同じ通知の宛先どうしにアドレスを見せない。
      # custom_args はイベント Webhook のイベントにそのまま載り、inbox の処理がテナントと送信記録を引く
      def body(message)
        {
          personalizations: message.to.map { { to: [ { email: _1 } ] } },
          from: { email: message.from },
          subject: message.subject,
          content: [ { type: "text/plain", value: message.body } ],
          custom_args: message.custom_args,
          mail_settings: { sandbox_mode: { enable: @sandbox } }
        }.to_json
      end

      def post(json)
        Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true,
          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: WRITE_TIMEOUT) do |http|
          request = Net::HTTP::Post.new(ENDPOINT)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          request.body = json
          http.request(request)
        end
      end

      def responded(status)
        Rails.event.notify("notifications.provider_responded", provider: "sendgrid", status:)
      end

      # 状態コードの百の位で分け、429 だけは別にする。コードごとに分けると、ラベルの値の種類が増える
      def status_class(status)
        status == 429 ? "429" : "#{status / 100}xx"
      end

      # 応答の本文は宛先のアドレスを含みうるので、失敗の理由には状態コードだけを書く。
      # sandbox mode の受け付けは 200 で、メッセージ ID のヘッダが無いことがあるので、無ければ空のまま受け付けとする
      def classify(response)
        status = response.code.to_i
        case status
        when 200, 202 then Accepted.new(message_id: response["X-Message-Id"])
        when 429 then raise RateLimited.new(wait: rate_limit_wait(response))
        when 500.. then raise TransientError, "http_#{status}"
        else raise PermanentError, "http_#{status}"
        end
      end

      # SendGrid の文書が示すのは X-RateLimit-Reset（制限が戻る時刻の UNIX 時刻）である。Retry-After（秒）が来れば先に使う
      def rate_limit_wait(response)
        seconds = if response["Retry-After"]&.match?(/\A\d+\z/)
          response["Retry-After"].to_i
        elsif response["X-RateLimit-Reset"]&.match?(/\A\d+\z/)
          response["X-RateLimit-Reset"].to_i - Time.current.to_i
        end
        seconds&.clamp(1, MAX_RATE_LIMIT_WAIT)
      end
    end
  end
end
