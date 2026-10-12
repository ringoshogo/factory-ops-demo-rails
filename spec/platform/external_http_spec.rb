require "rails_helper"

# テストから外部へ HTTP で出られない（docs/adr/007 決定 5）。送信先の設定を誤っても、本物の SendGrid に届かない
RSpec.describe "外部への HTTP" do
  it "外部のホストへの接続を、通信の層で止める" do
    expect { Net::HTTP.get(URI("https://api.sendgrid.com/v3/mail/send")) }.to raise_error(WebMock::NetConnectNotAllowedError)
  end
end
