class GraphqlController < ApplicationController
  # スキーマの実行全体を、セッションのテナントを設定した 1 つのトランザクションで包む。
  # トップレベルのエラーを返すか例外ならロールバックし、それ以外はユーザーエラーを返した場合も含めてコミットする
  def execute
    return head :unauthorized if session[:tenant_id].blank? || session[:user_id].blank?

    actor = result = nil
    Tenancy.with_tenant(session[:tenant_id]) do
      actor = Partnerships::Authentication.actor(session[:user_id], session_version: session[:session_version])
      next unless actor

      result = Current.set(actor: actor) do
        FactoryOpsSchema.execute(params[:query], variables: variables, operation_name: params[:operationName],
          context: { current_user: actor })
      end
      # graphql-ruby は FORBIDDEN などの GraphQL::ExecutionError を拾って errors に載せるので、例外としては届かない
      raise ActiveRecord::Rollback if result["errors"].present?
    end
    return head :unauthorized unless actor

    render json: result
  end

  private

  def variables
    variables = params[:variables]
    variables.respond_to?(:to_unsafe_h) ? variables.to_unsafe_h : {}
  end
end
