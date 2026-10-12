require "rails_helper"
require_relative "../support/tenant_helpers"

RSpec.describe "セッション", type: :request do
  include TenantHelpers

  let!(:tenant) { create_tenant("a") }
  let!(:user_id) { Tenancy.with_tenant(tenant) { insert_user(tenant, "a@example.com", password: "secret") } }

  def login(email:, password:, as: :json)
    post "/session", params: { email:, password: }, as:
  end

  describe "ログイン" do
    it "正しいパスワードならユーザーと所有テナントをセッションに保存する" do
      login(email: "A@example.com ", password: "secret")

      expect(response).to have_http_status(:no_content)
      expect(session[:user_id]).to eq(user_id)
      expect(session[:tenant_id]).to eq(tenant)
    end

    it "セッションの Cookie は SameSite=Lax で、JavaScript から読めない" do
      login(email: "a@example.com", password: "secret")

      cookie = response.headers["set-cookie"]
      expect(cookie).to match(/_factory_ops_session=/)
      expect(cookie).to match(/samesite=lax/i)
      expect(cookie).to match(/httponly/i)
    end

    it "パスワードが違えば 401 で、セッションに何も残さない" do
      login(email: "a@example.com", password: "wrong")

      expect(response).to have_http_status(:unauthorized)
      expect(session[:user_id]).to be_nil
    end

    it "存在しないメールアドレスでも、パスワード違いと同じ応答を返す" do
      login(email: "a@example.com", password: "wrong")
      wrong_password = [ response.status, response.body ]
      login(email: "nobody@example.com", password: "secret")

      expect([ response.status, response.body ]).to eq(wrong_password)
      expect(response).to have_http_status(:unauthorized)
    end

    it "保存されたダイジェストが bcrypt の形式でなくても、パスワード違いと同じ 401 を返す" do
      login(email: "a@example.com", password: "wrong")
      wrong_password = [ response.status, response.body ]
      Tenancy.with_tenant(tenant) { connection.update("UPDATE users SET password_digest = 'not-a-bcrypt-digest'") }
      login(email: "a@example.com", password: "secret")

      expect([ response.status, response.body ]).to eq(wrong_password)
    end

    it "application/json 以外は受け付けない" do
      login(email: "a@example.com", password: "secret", as: nil)

      expect(response).to have_http_status(:unsupported_media_type)
      expect(session[:user_id]).to be_nil
    end
  end

  describe "ログアウト" do
    it "セッションを消す" do
      login(email: "a@example.com", password: "secret")
      delete "/session", as: :json

      expect(response).to have_http_status(:no_content)
      expect(session[:user_id]).to be_nil
      expect(session[:tenant_id]).to be_nil
    end

    # 同じアカウントでログインしたもう 1 人の訪問者。別の Cookie を持つ
    def other_visitor
      open_session.tap do |visitor|
        visitor.post "/session", params: { email: "a@example.com", password: "secret" }, as: :json
        expect(visitor.response).to have_http_status(:no_content)
      end
    end

    def viewer_status(visitor)
      visitor.post "/graphql", params: { query: "{ viewer { id } }" }, as: :json
      visitor.response.status
    end

    it "セッションの世代を進め、同じユーザーのほかのセッションも切る" do
      visitor = other_visitor
      expect(viewer_status(visitor)).to eq(200)

      login(email: "a@example.com", password: "secret")
      delete "/session", as: :json

      expect(viewer_status(visitor)).to eq(401)
    end

    # 公開の配置では、全員がログインの画面に並ぶ同じアカウントを使う（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
    it "共有のデモのアカウントの配置では、世代を進めず、ほかのセッションが続く" do
      allow(Rails.configuration.x).to receive(:shared_demo_accounts).and_return(true)
      visitor = other_visitor

      login(email: "a@example.com", password: "secret")
      delete "/session", as: :json

      expect(response).to have_http_status(:no_content)
      expect(session[:user_id]).to be_nil
      expect(viewer_status(visitor)).to eq(200)
    end
  end
end
