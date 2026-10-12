# 通知の送信先を起動時に作り、本番以外で SendGrid の sandbox mode を外した設定を、最初の送信を待たずに止める
# （docs/adr/007 決定 5 の A-2）
Rails.application.config.after_initialize { Notifications::Setup.verify! }
