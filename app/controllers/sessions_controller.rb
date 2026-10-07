# ログインとログアウト。GraphQL に認証の mutation は置かない（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
class SessionsController < ApplicationController
  def create
    login = Partnerships::Authentication.authenticate(email: params[:email], password: params[:password])
    return head :unauthorized unless login

    # セッション固定を防ぐ
    reset_session
    session[:user_id] = login.user_id
    session[:tenant_id] = login.tenant_id
    head :no_content
  end

  def destroy
    reset_session
    head :no_content
  end
end
