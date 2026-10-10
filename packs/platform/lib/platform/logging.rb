require_relative "json_log_formatter"

module Platform
  # ログの書式（docs/guides/config.md「ログ」）。本番とテストの環境のファイルが configure! を呼ぶ。
  # JSON の書式は文字列の中の秘密やクエリの本文を消さないので、値を文字列のまま Rails.logger に書くフレームワークの経路を止める
  module Logging
    # TaggedLogging で包まない。タグを文字列としてメッセージの前に付けてから書式に渡すので、行が JSON で始まらない
    def self.build(io)
      ActiveSupport::Logger.new(io).tap { _1.formatter = JsonLogFormatter.new }
    end

    def self.configure!(config, io)
      config.logger = build(io)
      config.log_tags = []
      # 要求の開始の行に filtered_path を書く。filter_parameters は名前で隠すだけなので、URL の query・variables の値が残る
      config.middleware.delete Rails::Rack::Logger
      # 捕まえた例外のメッセージとバックトレースを書く。例外は ActionDispatch::Executor がエラー通知に送る
      config.middleware.delete ActionDispatch::DebugExceptions
      config.after_initialize { detach_string_log_subscribers }
    end

    # 構造化イベントと同じ内容を、params・ジョブの引数・例外のメッセージ込みの文字列で書く購読。
    # 購読は読み込んだ時点で付くので、先に読み込んでから外す
    def self.detach_string_log_subscribers
      require "action_controller/log_subscriber"
      require "action_dispatch/log_subscriber"
      require "active_job/log_subscriber"
      require "solid_queue/log_subscriber"
      ActionController::LogSubscriber.detach_from :action_controller
      ActionDispatch::LogSubscriber.detach_from :action_dispatch
      ActiveJob::LogSubscriber.detach_from :active_job
      # ワーカーのスレッドで上がったジョブの例外を、メッセージ込みで書く
      SolidQueue::LogSubscriber.detach_from :solid_queue
    end
  end
end
