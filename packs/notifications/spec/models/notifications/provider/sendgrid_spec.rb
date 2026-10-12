require "rails_helper"

# SendGrid の送信 API の応答と例外の分け方（docs/adr/007 決定 5 の A-2 の表）。WebMock のスタブで応答を返し、本物の SendGrid は呼ばない
RSpec.describe Notifications::Provider::Sendgrid do
  include ActiveSupport::Testing::TimeHelpers

  let(:provider) { described_class.new(api_key: "SG.test-key", sandbox: true, production: false) }
  let(:message) do
    Notifications::Provider::Message.new(from: "from@example.com", to: %w[a@example.com b@example.com], subject: "件名",
      body: "本文", custom_args: { "tenant_id" => "t1", "email_delivery_id" => "d1" })
  end
  let(:endpoint) { "https://api.sendgrid.com/v3/mail/send" }

  def stub_status(status, headers = {})
    stub_request(:post, endpoint).to_return(status:, headers:, body: "")
  end

  def failure
    provider.deliver(message)
    nil
  rescue Notifications::Provider::Error => error
    error
  end

  describe "受け付け" do
    it "202 は受け付けで、メッセージ ID のヘッダを返す" do
      stub_status(202, "X-Message-Id" => "msg-1")

      expect(provider.deliver(message)).to eq(Notifications::Provider::Accepted.new(message_id: "msg-1"))
    end

    it "sandbox mode の 200 は、メッセージ ID のヘッダが無くても受け付けにする" do
      stub_status(200)

      expect(provider.deliver(message)).to eq(Notifications::Provider::Accepted.new(message_id: nil))
    end

    it "宛先ごとに personalization を分け、custom_args・sandbox mode・API キーを付けて送る" do
      stub_status(202)

      provider.deliver(message)

      expect(WebMock).to(have_requested(:post, endpoint).with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer SG.test-key" &&
          body["personalizations"] == [ { "to" => [ { "email" => "a@example.com" } ] }, { "to" => [ { "email" => "b@example.com" } ] } ] &&
          body["custom_args"] == { "tenant_id" => "t1", "email_delivery_id" => "d1" } &&
          body["mail_settings"] == { "sandbox_mode" => { "enable" => true } } &&
          body["content"] == [ { "type" => "text/plain", "value" => "本文" } ]
      end)
    end

    it "時間切れを、接続 5 秒・読み書き 10 秒にする" do
      stub_status(202)
      expect(Net::HTTP).to receive(:start)
        .with("api.sendgrid.com", 443, hash_including(use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 10))
        .and_call_original

      provider.deliver(message)
    end
  end

  describe "429" do
    it "Retry-After の秒数を待ち時間にする" do
      stub_status(429, "Retry-After" => "30")

      expect(failure).to be_a(Notifications::Provider::RateLimited).and have_attributes(wait: 30)
    end

    it "Retry-After が無ければ、X-RateLimit-Reset の時刻までを待ち時間にする" do
      travel_to Time.zone.at(1_800_000_000) do
        stub_status(429, "X-RateLimit-Reset" => "1800000045")

        expect(failure).to have_attributes(wait: 45)
      end
    end

    it "待ち時間は 1 時間で頭打ちにし、過ぎた時刻なら 1 秒にする" do
      travel_to Time.zone.at(1_800_000_000) do
        stub_status(429, "X-RateLimit-Reset" => "1800009000")
        expect(failure).to have_attributes(wait: 3600)

        stub_status(429, "X-RateLimit-Reset" => "1799999000")
        expect(failure).to have_attributes(wait: 1)
      end
    end

    it "待ち時間のヘッダが無ければ nil にし、間隔はジョブの再試行に任せる" do
      stub_status(429)

      expect(failure).to be_a(Notifications::Provider::RateLimited).and have_attributes(wait: nil)
    end
  end

  it "5xx は再試行する失敗にする" do
    [ 500, 503 ].each do |status|
      stub_status(status)

      expect(failure).to be_a(Notifications::Provider::TransientError).and have_attributes(message: "http_#{status}")
    end
  end

  it "400・401・403・413 は、状態コードだけを理由にした再試行しない失敗にする" do
    [ 400, 401, 403, 413 ].each do |status|
      stub_request(:post, endpoint).to_return(status:, body: '{"errors":[{"message":"a@example.com is invalid"}]}')

      expect(failure).to be_a(Notifications::Provider::PermanentError).and have_attributes(message: "http_#{status}")
    end
  end

  it "タイムアウトと接続の失敗は、再試行する失敗にする" do
    [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT, SocketError, EOFError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse ].each do |error|
      stub_request(:post, endpoint).to_raise(error)

      expect(failure).to be_a(Notifications::Provider::TransientError).and have_attributes(message: error.name)
    end
  end

  # メトリクスの external_requests_total の出どころ（docs/guides/config.md「メトリクス」）
  describe "応答の種類のイベント" do
    let(:events) { [] }
    let(:collector) { Struct.new(:events) { def emit(event) = events << event }.new(events) }

    around do |example|
      Rails.event.subscribe(collector)
      example.run
    ensure
      Rails.event.unsubscribe(collector)
    end

    def responded = events.select { _1[:name] == "notifications.provider_responded" }.map { _1[:payload] }

    it "状態コードを百の位で分け、429 だけを別にし、接続の失敗を timeout にして 1 回ずつ出す" do
      [ 202, 200, 429, 400, 413, 500, 503 ].each do |status|
        stub_status(status)
        failure
      end
      stub_request(:post, endpoint).to_raise(Net::ReadTimeout)
      failure

      expect(responded.map { _1[:status] }).to eq(%w[2xx 2xx 429 4xx 4xx 5xx 5xx timeout])
      expect(responded.map { _1[:provider] }.uniq).to eq([ "sendgrid" ])
    end

    it "API キーが無く送らなかったときは出さない" do
      provider = described_class.new(api_key: nil, sandbox: true, production: false)
      stub_status(202)

      expect { provider.deliver(message) }.to raise_error(Notifications::Provider::PermanentError)
      provider = described_class.new(api_key: "SG.test-key", sandbox: true, production: false)
      provider.deliver(message)
      expect(responded).to eq([ { provider: "sendgrid", status: "2xx" } ])
    end
  end

  it "API キーが無ければ、送らずに再試行しない失敗にする" do
    provider = described_class.new(api_key: nil, sandbox: true, production: false)

    expect { provider.deliver(message) }.to raise_error(Notifications::Provider::PermanentError, "missing_api_key")
    expect(WebMock).not_to have_requested(:post, endpoint)
  end

  it "本番以外では、sandbox mode を外すと作れない。本番では外せる" do
    expect { described_class.new(api_key: "k", sandbox: false, production: false) }
      .to raise_error(described_class::SandboxRequired)
    expect(described_class.new(api_key: "k", sandbox: false, production: true)).to be_a(described_class)
  end

  it "inspect に API キーを出さない" do
    expect(provider.inspect).not_to include("SG.test-key")
  end
end
