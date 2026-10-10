module Platform
  # 要求の文脈（要求 ID と相関 ID）を、Rails が要求のイベントを出す区間より外側で設定する。
  # 利用者の要求は一連の処理の始まりなので、要求 ID を相関 ID にする。
  # 文脈を空に戻すのは、外側の ActionDispatch::Executor である（docs/guides/config.md「ログ」）
  class RequestContext
    def initialize(app)
      @app = app
    end

    def call(env)
      request_id = env["action_dispatch.request_id"]
      context = { request_id:, correlation_id: request_id }
      ActiveSupport.event_reporter.set_context(context)
      ActiveSupport.error_reporter.set_context(**context)
      @app.call(env)
    end
  end
end
