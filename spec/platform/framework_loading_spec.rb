require "rails_helper"

# 読み込む Rails の部品を、使うものに限る（docs/guides/config.md「application.rb で変えたこと」）。
# 読み込まれた部品があると、読む人がそれを使える前提で設計するので、使わない部品の定数が無いことを起動の後に見る
RSpec.describe "読み込む Rails の部品" do
  it "ファイルの添付・メールの受信・リッチテキスト・WebSocket の部品を読み込まない" do
    expect(%w[ActiveStorage::Engine ActionMailbox::Engine ActionText::Engine ActionCable::Engine]
      .select { Object.const_defined?(_1) }).to eq([])
  end

  it "通知のメールを送る Action Mailer は読み込む" do
    expect(Object.const_defined?("ActionMailer::Base")).to be(true)
  end
end
