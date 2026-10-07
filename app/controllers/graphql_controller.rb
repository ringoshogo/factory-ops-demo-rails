class GraphqlController < ApplicationController
  # スキーマの実行全体を、セッションのテナントを設定した 1 つのトランザクションで包む。
  # 例外ならロールバックし、それ以外はユーザーエラーを返した場合も含めてコミットする
  def execute
    return head :unauthorized if session[:tenant_id].blank? || session[:user_id].blank?

    result = Tenancy.with_tenant(session[:tenant_id]) do
      actor = Partnerships::Authentication.actor(session[:user_id])
      next unless actor

      Current.set(actor: actor) do
        FactoryOpsSchema.execute(params[:query], variables: variables, operation_name: params[:operationName],
          context: { current_user: actor })
      end
    end
    return head :unauthorized unless result

    render json: result
  end

  private

  def variables
    variables = params[:variables]
    variables.respond_to?(:to_unsafe_h) ? variables.to_unsafe_h : {}
  end
end
