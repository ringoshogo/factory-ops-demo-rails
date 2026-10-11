module Notifications
  module Provider
    # 開発の送信先。1 通を 1 ファイルに書き、外部へは送らない
    class FileSystem
      def initialize(dir)
        @dir = Pathname(dir)
      end

      def deliver(message)
        @dir.mkpath
        message_id = SecureRandom.uuid
        @dir.join("#{Time.current.strftime('%Y%m%d%H%M%S')}-#{message_id}.txt").write(<<~MAIL)
          From: #{message.from}
          To: #{message.to.join(', ')}
          Subject: #{message.subject}
          Custom-Args: #{message.custom_args.to_json}

          #{message.body}
        MAIL
        Accepted.new(message_id:)
      end
    end
  end
end
