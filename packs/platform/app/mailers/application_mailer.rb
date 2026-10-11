# メールの基底クラス。パッケージのメール（Notifications::Mailer）が継承するので、ApplicationJob と同じく platform に置く
class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"
end
