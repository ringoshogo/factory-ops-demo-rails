# ログインとログアウト。GraphQL に認証の mutation は置かない（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
class SessionsController < ApplicationController
  def create
    login = Partnerships::Authentication.authenticate(email: params[:email], password: params[:password])
    return head :unauthorized unless login

    # セッション固定を防ぐ
    reset_session
    session[:user_id] = login.user_id
    session[:tenant_id] = login.tenant_id
    session[:session_version] = login.session_version
    head :no_content
  end

  # Cookie のセッションはサーバーに残らないので、消すだけでは写した Cookie が使える。ユーザーの世代を進めて無効にする
  def destroy
    if session[:tenant_id].present? && session[:user_id].present?
      Tenancy.with_tenant(session[:tenant_id]) do
        Partnerships::Authentication.revoke_sessions(session[:user_id], session_version: session[:session_version])
      end
    end
    reset_session
    head :no_content
  end
end
