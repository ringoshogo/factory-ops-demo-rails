module Notifications
  # 起動時の確かめ（config/initializers/notifications.rb）。送信先を設定から作り、本番以外で SendGrid の sandbox mode を
  # 外した設定を、最初の送信を待たずに例外にする
  module Setup
    # 送信先（内部の Provider）を外へ出さない
    def self.verify!
      Provider.reset!
      Provider.current
      nil
    end
  end
end
