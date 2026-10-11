module Notifications
  # テストの送信先（config/environments/test.rb）。送ったメールをメモリに積み、テストから読める。
  # fail_next に積んだ例外は、次の送信で 1 つずつ投げる。spec/rails_helper.rb が example ごとに空にする
  module FakeProvider
    MUTEX = Mutex.new
    @deliveries = []
    @failures = []

    class << self
      def deliver(message)
        MUTEX.synchronize do
          raise @failures.shift if @failures.any?

          @deliveries << message
        end
        Notifications::Provider::Accepted.new(message_id: "fake-#{SecureRandom.uuid}")
      end

      def deliveries = MUTEX.synchronize { @deliveries.dup }

      def fail_next(*errors) = MUTEX.synchronize { @failures.concat(errors) }

      def clear
        MUTEX.synchronize do
          @deliveries.clear
          @failures.clear
        end
      end
    end
  end
end
