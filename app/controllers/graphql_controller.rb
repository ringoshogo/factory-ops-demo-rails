class GraphqlController < ApplicationController
  # スキーマの実行全体を、セッションのテナントを設定した 1 つのトランザクションで包む。
  # トップレベルのエラーを返すか例外ならロールバックし、それ以外はユーザーエラーを返した場合も含めてコミットする
  def execute
    return head :unauthorized if session[:tenant_id].blank? || session[:user_id].blank?

    actor = result = nil
    Tenancy.with_tenant(session[:tenant_id]) do
      actor = Partnerships::Authentication.actor(session[:user_id], session_version: session[:session_version])
      next unless actor

      set_log_context(actor)
      result = Current.set(actor: actor) { execute_operation(actor) }
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

  def operation_name
    params[:operationName].presence || "anonymous"
  end

  # スキーマを実行する前に設定する。Rails.event の文脈は Fiber のストレージにあり、Dataloader が作る Fiber は
  # 作られた時点の値を写して持つので、Fiber の中で設定した値は親に戻らない（docs/guides/config.md「ログ」）
  def set_log_context(actor)
    context = { tenant_id: actor.tenant_id, user_id: actor.user_id }
    Rails.event.set_context(**context, graphql_operation: operation_name)
    Rails.error.set_context(**context)
  end

  def execute_operation(actor)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = FactoryOpsSchema.execute(params[:query], variables: variables, operation_name: params[:operationName],
      context: { current_user: actor })
    codes = result.context[:user_error_codes] || []
    Rails.event.notify("graphql.operation_completed", operation_name:, result: outcome(result, codes), user_error_codes: codes,
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2))
    result
  end

  def outcome(result, user_error_codes)
    if result["errors"].present? then "error"
    elsif user_error_codes.any? then "user_error"
    else "success"
    end
  end
end
