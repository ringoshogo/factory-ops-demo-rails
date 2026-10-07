require "rails_helper"
require_relative "../support/tenant_helpers"

# GraphQL の入口（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
RSpec.describe "GraphQL の入口", type: :request do
  include TenantHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:session_cookie) { "_factory_ops_session" }

  let!(:tenant_a) { create_tenant("a") }
  let!(:tenant_b) { create_tenant("b") }
  let!(:user_a) { Tenancy.with_tenant(tenant_a) { insert_user(tenant_a, "a@example.com") } }

  def login_as(email)
    post "/session", params: { email:, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def execute_graphql(query = "{ viewer { id email } }", as: :json)
    post "/graphql", params: { query: }, as:
  end

  # スキーマの実行に割り込み、実行中の DB の状態を読む
  def during_execution
    allow(FactoryOpsSchema).to receive(:execute).and_wrap_original do |original, *args, **kwargs|
      yield
      original.call(*args, **kwargs)
    end
  end

  it "ログイン中のユーザーを viewer で返す" do
    login_as("a@example.com")
    execute_graphql

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "viewer")).to eq("id" => user_a, "email" => "a@example.com")
  end

  describe "認証" do
    it "未ログインなら実行せずに 401" do
      expect(FactoryOpsSchema).not_to receive(:execute)
      execute_graphql

      expect(response).to have_http_status(:unauthorized)
    end

    it "セッションのテナントでユーザーが引けなければ（別テナントのセッション）実行せずに 401" do
      allow(Partnerships::Authentication).to receive(:authenticate)
        .and_return(Partnerships::Authentication::Login.new(user_id: user_a, tenant_id: tenant_b, session_version: 0))
      login_as("a@example.com")

      expect(FactoryOpsSchema).not_to receive(:execute)
      execute_graphql

      expect(response).to have_http_status(:unauthorized)
    end

    it "ログアウトの後は 401" do
      login_as("a@example.com")
      delete "/session", as: :json
      execute_graphql

      expect(response).to have_http_status(:unauthorized)
    end

    # Cookie のセッションはサーバーに残らないので、ログアウトの前に写した Cookie はそのままでは使えてしまう
    it "ログアウトの前の Cookie を送り直しても 401" do
      login_as("a@example.com")
      stolen = cookies[session_cookie]
      delete "/session", as: :json
      cookies[session_cookie] = stolen
      execute_graphql

      expect(response).to have_http_status(:unauthorized)
    end

    it "無効になった Cookie でログアウトしても、新しいセッションは切れない" do
      login_as("a@example.com")
      stolen = cookies[session_cookie]
      delete "/session", as: :json
      login_as("a@example.com")
      current = cookies[session_cookie]
      cookies[session_cookie] = stolen
      delete "/session", as: :json
      cookies[session_cookie] = current
      execute_graphql

      expect(response).to have_http_status(:ok)
    end

    it "パスワードを変えると、変える前のセッションは 401" do
      login_as("a@example.com")
      # 世代は DB のトリガーが進めるので、パスワードを書き換える経路を問わない
      digest = BCrypt::Password.create("changed-password", cost: BCrypt::Engine::MIN_COST)
      Tenancy.with_tenant(tenant_a) { connection.update("UPDATE users SET password_digest = #{connection.quote(digest)}") }
      execute_graphql

      expect(response).to have_http_status(:unauthorized)
    end

    it "パスワード以外を変えても、セッションは続く" do
      login_as("a@example.com")
      Tenancy.with_tenant(tenant_a) { connection.update("UPDATE users SET name = 'renamed', password_digest = password_digest") }
      execute_graphql

      expect(response).to have_http_status(:ok)
    end

    it "最後のリクエストから 12 時間を過ぎたセッションは 401" do
      login_as("a@example.com")
      travel 12.hours + 1.minute
      execute_graphql

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "CSRF" do
    before { login_as("a@example.com") }

    it "GET は受け付けない" do
      get "/graphql", params: { query: "{ viewer { id } }" }

      expect(response).to have_http_status(:not_found)
    end

    it "application/json 以外の POST は実行しない" do
      expect(FactoryOpsSchema).not_to receive(:execute)
      execute_graphql(as: nil)

      expect(response).to have_http_status(:unsupported_media_type)
    end
  end

  describe "トランザクションとテナント" do
    before { login_as("a@example.com") }

    it "実行中はリクエストのトランザクションの中で、app.tenant_id がセッションのテナントで、Current も設定されている" do
      # テストはトランザクションの中で動くので、それより 1 段深いことを確かめる
      outside = connection.open_transactions
      seen = {}
      during_execution do
        seen[:depth] = connection.open_transactions - outside
        seen[:setting] = tenant_setting
        seen[:actor] = Current.actor&.user_id
      end
      execute_graphql

      expect(seen).to eq(depth: 1, setting: tenant_a, actor: user_a)
    end

    it "実行後は app.tenant_id が空に戻り、生 SQL が 0 行になる" do
      execute_graphql

      expect(tenant_setting).to eq("")
      expect(connection.select_value("SELECT count(*) FROM users")).to eq(0)
    end

    it "例外ならロールバックする" do
      during_execution do
        connection.update("UPDATE users SET name = 'changed'")
        raise "boom"
      end

      expect { execute_graphql }.to raise_error("boom")
      expect(tenant_setting).to eq("")
      expect(Tenancy.with_tenant(tenant_a) { connection.select_value("SELECT name FROM users") }).to eq("name")
    end

    it "トップレベルのエラーが無ければコミットする" do
      during_execution { connection.update("UPDATE users SET name = 'changed'") }
      execute_graphql

      expect(response.parsed_body).not_to have_key("errors")
      expect(Tenancy.with_tenant(tenant_a) { connection.select_value("SELECT name FROM users") }).to eq("changed")
    end

    # graphql-ruby は GraphQL::ExecutionError を拾って errors に載せるので、例外としてはコントローラに届かない
    it "書き込みの後に FORBIDDEN を返すとロールバックする" do
      during_execution { connection.update("UPDATE users SET name = 'changed'") }
      allow(Types::ViewerType).to receive(:authorized?).and_return(false)
      execute_graphql

      expect(response.parsed_body["errors"].map { |error| error.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      expect(tenant_setting).to eq("")
      expect(Tenancy.with_tenant(tenant_a) { connection.select_value("SELECT name FROM users") }).to eq("name")
    end

    it "クエリの検証で落ちたときもロールバックする" do
      during_execution { connection.update("UPDATE users SET name = 'changed'") }
      execute_graphql("{ viewer { unknownField } }")

      expect(response.parsed_body["errors"]).to be_present
      expect(Tenancy.with_tenant(tenant_a) { connection.select_value("SELECT name FROM users") }).to eq("name")
    end
  end
end
