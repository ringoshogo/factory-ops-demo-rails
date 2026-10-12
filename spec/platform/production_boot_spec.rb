require "rails_helper"
require "open3"

# 本番の環境の起動と、公開の配置が環境変数で決める設定（docs/guides/config.md「環境ごとの設定」、docs/adr/009 決定 2）。
# 本番の環境はテストのプロセスと設定が違うので、spec/platform/logging_spec.rb と同じく子のプロセスで初期化して見る。
# 本番の環境の DB はテストと CI に無いので、DB に触れる公開 API は子のプロセスの中で差し替える
RSpec.describe "本番の環境の起動" do
  # 子のプロセスで本番の環境を初期化し、script の後半を流す。script は SPEC_RESULT に続けて JSON を 1 行書く
  def boot_production(env = {}, script = "")
    source = <<~RUBY
      require "./config/application"
      Rails.application.initialize!
      #{script}
    RUBY
    base = { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x", "RAILS_LOG_LEVEL" => nil, "NOTIFICATIONS_PROVIDER" => nil,
      "DB_HOST" => nil, "DB_PORT" => nil, "DB_OWNER_USER" => nil, "SHARED_DEMO_ACCOUNTS" => nil }
    Open3.capture2e(base.merge(env), RbConfig.ruby, "-e", source, chdir: Rails.root.to_s)
  end

  def result_of(output, status)
    expect(status).to be_success, output
    JSON.parse(output.lines.grep(/\ASPEC_RESULT /).sole.delete_prefix("SPEC_RESULT "))
  end

  describe "通知の送り先（NOTIFICATIONS_PROVIDER）" do
    let(:print_provider) { 'puts "SPEC_RESULT " + JSON.generate(provider: Rails.configuration.x.notifications.provider)' }

    it "省けば SendGrid に、file_system ならファイルに送る" do
      expect(result_of(*boot_production({}, print_provider))).to eq("provider" => "sendgrid")
      expect(result_of(*boot_production({ "NOTIFICATIONS_PROVIDER" => "file_system" }, print_provider))).to eq("provider" => "file_system")
    end

    it "ほかの値では起動しない" do
      [ "fake", "smtp", "" ].each do |value|
        output, status = boot_production({ "NOTIFICATIONS_PROVIDER" => value }, print_provider)

        expect(status).not_to be_success, "起動した: #{value.inspect}"
        expect(output).to include("NOTIFICATIONS_PROVIDER")
      end
    end
  end

  # ログアウトでセッションの世代を進めないのは、1 を渡したときだけである（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
  it "SHARED_DEMO_ACCOUNTS が 1 のときだけ、共有のデモのアカウントの設定を真にする" do
    script = 'puts "SPEC_RESULT " + JSON.generate(shared: Rails.configuration.x.shared_demo_accounts)'

    expect([ nil, "1", "true" ].map { result_of(*boot_production({ "SHARED_DEMO_ACCOUNTS" => _1 }, script)).fetch("shared") }).to eq([ false, true, false ])
  end

  # TLS は Cloudflare で終わり、Rails には Next のサーバーから http で届く。Secure の Cookie を http の応答にも書く
  it "http の POST /session の応答が、Secure のセッションの Cookie を Set-Cookie に持つ" do
    script = <<~RUBY
      login = Partnerships::Authentication::Login.new(user_id: SecureRandom.uuid, tenant_id: SecureRandom.uuid, session_version: 0)
      Partnerships::Authentication.define_singleton_method(:authenticate) { |**| login }
      response = Rack::MockRequest.new(Rails.application).post("http://web:3000/session",
        "CONTENT_TYPE" => "application/json", input: JSON.generate(email: "a@example.com", password: "x"))
      puts "SPEC_RESULT " + JSON.generate(status: response.status, set_cookie: response.headers["set-cookie"].to_s)
    RUBY

    result = result_of(*boot_production({}, script))

    expect(result.fetch("status")).to eq(204)
    expect(result.fetch("set_cookie")).to match(/\A_factory_ops_session=/)
    expect(result.fetch("set_cookie").split(";").map { _1.strip.downcase }).to include("secure")
  end

  # 所有ロールの設定は DB_OWNER_USER を渡したプロセスにだけ置く（config/database.yml）
  it "DB の接続先を DB_HOST と DB_PORT で決め、所有ロールの設定は DB_OWNER_USER を渡したときだけ置く" do
    script = <<~RUBY
      configs = ActiveRecord::Base.configurations.configs_for(env_name: "production", include_hidden: true)
      puts "SPEC_RESULT " + JSON.generate(configs.to_h { [ _1.name, _1.configuration_hash.slice(:host, :port, :username) ] })
    RUBY
    env = { "DB_HOST" => "postgres", "DB_PORT" => "5432", "DB_APP_USER" => "factory_app" }

    expect(result_of(*boot_production(env, script))).to eq("primary" => { "host" => "postgres", "port" => 5432, "username" => "factory_app" })
    expect(result_of(*boot_production(env.merge("DB_OWNER_USER" => "factory_owner"), script))).to eq(
      "primary" => { "host" => "postgres", "port" => 5432, "username" => "factory_app" },
      "owner" => { "host" => "postgres", "port" => 5432, "username" => "factory_owner" }
    )
  end
end
