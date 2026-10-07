require "rails_helper"
require_relative "../support/tenant_helpers"

# GraphQL の入口（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
RSpec.describe "GraphQL の入口", type: :request do
  include TenantHelpers

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
        .and_return(Partnerships::Authentication::Login.new(user_id: user_a, tenant_id: tenant_b))
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

    it "ユーザーエラーを返した場合はコミットする" do
      during_execution { connection.update("UPDATE users SET name = 'changed'") }
      execute_graphql("{ viewer { unknownField } }")

      expect(response.parsed_body["errors"]).to be_present
      expect(Tenancy.with_tenant(tenant_a) { connection.select_value("SELECT name FROM users") }).to eq("changed")
    end
  end
end
