module Notifications
  # 送信のジョブが、提供元の失敗から再試行の待ち時間を決める。429 は応答が示した待ち時間に従い、示さなければ、
  # 5xx・タイムアウトと同じく実行の回数に応じて間隔を延ばす（docs/adr/007 決定 5）。回数は 429 と 5xx を合わせて数える
  module ProviderRetry
    private

    def retry_wait(error)
      (error.is_a?(Provider::RateLimited) && error.wait) ||
        determine_delay(seconds_or_duration_or_algorithm: :polynomially_longer, executions:)
    end

    def retries_left?
      executions < self.class::ATTEMPTS
    end
  end
end
