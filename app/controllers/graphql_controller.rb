class GraphqlController < ApplicationController
  include MaintenanceMode

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

  # 操作名は利用者が送る値なので、GraphQL の名前の形の文字列でなければログに書かない
  def operation_name
    name = params[:operationName]
    name.blank? ? "anonymous" : Platform::JsonLogSubscriber.graphql_name(name)
  end

  # スキーマを実行する前に設定する。Rails.event の文脈は Fiber のストレージにあり、Dataloader が作る Fiber は
  # 作られた時点の値を写して持つので、Fiber の中で設定した値は親に戻らない（docs/guides/config.md「ログ」）
  def set_log_context(actor)
    context = { tenant_id: actor.tenant_id, user_id: actor.user_id }
    Rails.event.set_context({ **context, graphql_operation: operation_name }.compact)
    Rails.error.set_context(**context)
  end

  # 操作の終わりのイベントは、スキーマの実行が例外を上げたときも ensure で 1 回だけ出す。正常に戻ったときだけ出すと、
  # 500 になった操作がメトリクスの成功の割合の分母から抜ける。context は graphql-ruby がそのまま持つハッシュなので、
  # 例外の後も、実行中に積んだユーザーエラーのコードを読める
  def execute_operation(actor)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    context = { current_user: actor }
    result = FactoryOpsSchema.execute(params[:query], variables: variables, operation_name: params[:operationName], context:)
  ensure
    user_error_codes = context[:user_error_codes] || []
    Rails.event.notify("graphql.operation_completed", operation_name:, operation_type: operation_type(result),
      result: outcome(result, user_error_codes), user_error_codes:, error_codes: error_codes(result),
      forbidden_reasons: forbidden_reasons(result),
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2))
  end

  # 文書を解析できないか、実行する操作を 1 つに決められないときは none にする。例外のときは結果が無いので、文書を解析し直す。
  # 文字列でない query は解析し直しでも例外になり、ensure の中で元の例外を置き換えるので、解析しない
  def operation_type(result)
    return "none" unless result || params[:query].is_a?(String)

    query = result&.query || GraphQL::Query.new(FactoryOpsSchema, params[:query], operation_name: params[:operationName])
    query.selected_operation&.operation_type || "none"
  end

  # 応答に載った FORBIDDEN の出どころ。graphql-ruby 2.6.11 は、null が伝わって消えた位置のエラーを context.errors に載せない
  # （lib/graphql/execution/interpreter/runtime.rb の continue_value）ので、拒否した箇所で数えると応答の FORBIDDEN より多くなる
  def forbidden_reasons(result)
    result ? result.context.errors.grep(ForbiddenError).map(&:reason) : []
  end

  # トップレベルのエラーの extensions.code。解析の失敗のように code を持たないエラーは none にする
  def error_codes(result)
    errors = result ? result["errors"].to_a : []
    errors.map { _1.dig("extensions", "code") || "none" }
  end

  def outcome(result, user_error_codes)
    if result.nil? || result["errors"].present? then "error"
    elsif user_error_codes.any? then "user_error"
    else "success"
    end
  end
end
