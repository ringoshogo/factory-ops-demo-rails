require "rails_helper"

# 送信先の切り替え（docs/adr/007 決定 5 の A-2）。テストと開発で本物の SendGrid を呼べない
RSpec.describe Notifications::Provider do
  def config(**values) = ActiveSupport::OrderedOptions.new.merge!(values)

  it "テストの環境の送信先はメモリで、開発はファイルにする" do
    expect(described_class.current).to eq(Notifications::FakeProvider)
    expect(described_class.build(config(provider: :file_system))).to be_a(described_class::FileSystem)
  end

  it "本番以外で SendGrid を選ぶと、sandbox mode を有効にしない限り作れない" do
    expect { described_class.build(config(provider: :sendgrid, sendgrid_api_key: "k")) }
      .to raise_error(described_class::Sendgrid::SandboxRequired)
    expect(described_class.build(config(provider: :sendgrid, sendgrid_api_key: "k", sendgrid_sandbox: true)))
      .to be_a(described_class::Sendgrid)
  end

  it "送信先を決めない設定は例外にする" do
    expect { described_class.build(config) }.to raise_error(ArgumentError, /provider/)
  end

  # 起動時の確かめは送信先を外へ出さない。送信先は Provider.current だけが返す
  it "起動時の確かめが、送信先を返さずに、設定から送信先を作り直す" do
    described_class.instance_variable_set(:@current, described_class::FileSystem.new(Dir.tmpdir))
    # 対照：作り直す前は、設定と違う送信先が残っている
    expect(described_class.current).to be_a(described_class::FileSystem)

    expect(Notifications::Setup.verify!).to be_nil
    expect(described_class.current).to eq(Notifications::FakeProvider)
  ensure
    described_class.reset!
  end

  describe described_class::FileSystem do
    it "1 通を 1 ファイルに書く" do
      Dir.mktmpdir do |dir|
        message = described_class.module_parent::Message.new(from: "f@example.com", to: [ "a@example.com" ], subject: "件名",
          body: "本文", custom_args: { "tenant_id" => "t1" })

        accepted = described_class.new(dir).deliver(message)

        files = Dir[File.join(dir, "*.txt")]
        expect(files.size).to eq(1)
        expect(File.read(files.first)).to include("To: a@example.com", "Subject: 件名", "本文")
        expect(accepted.message_id).to be_present
      end
    end
  end
end
