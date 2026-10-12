module Mutations
  # mutation は perspective と authorize_with <Policy>, :<規則> と、audit か audit_exempt を宣言し、perform で公開 API を呼んで
  # OperationResult を返す。対象を引く mutation は find_target を定義する。規則は対象を引いた後に対象に対して、作成系は操作者に対して評価する
  class BaseMutation < GraphQL::Schema::Mutation
    include GraphQL::Schema::HasSingleInputArgument
    # action_policy-graphql は field_class に拡張を prepend するので、GraphQL::Schema::Field に入らないよう先に差し替える
    field_class Types::BaseField
    object_class Types::BasePayload
    include ActionPolicy::GraphQL::Behaviour
    include AuthorizationDeclarations

    # 戻り値は null を許さない。規則による拒否の null が data まで伝わり、同じ要求で先に成功した mutation の payload も返さない。
    # トップレベルのエラーがある要求は書き込みをすべて戻すので、成功の payload を返すと、戻した書き込みを成功に見せる
    null false

    field :errors, [ Types::UserErrorType ], null: false

    # 成功したときに値を返すフィールド。失敗したときは空になる
    def self.result_field(name, type)
      field name, type
      @result_field_name = name
    end

    # 相手テナントに効果が及ぶ操作の監査の宣言（docs/architecture/graphql-schema.md「監査ログ」）。target と counterparty は
    # ラムダで、perform が成功の値を返した後に、成功の値（result:）・find_target で引いた対象（target:）・入力（input:）を
    # 受け取り、mutation の中で評価する。target は公開 API の値を返し、型の名前は値のクラス名から取る。
    # 相手を 1 つに決められない操作（カタログを見る全相手に及ぶものなど）は counterparty: nil にする
    def self.audit(action, target:, counterparty:)
      @audit = { action:, target:, counterparty: }
    end

    # 効果が自社の中で閉じる操作
    def self.audit_exempt(reason:)
      @audit_exempt_reason = reason
    end

    class << self
      attr_reader :result_field_name, :audit_exempt_reason

      def audit_action = @audit&.fetch(:action)
      def audit_declaration = @audit
      def audit_declared? = audit_action.present? || audit_exempt_reason.present?
      def missing_declarations = super + (audit_declared? ? [] : [ "audit" ])
    end

    def authorized?(**inputs)
      self.class.check_declarations!(context)
      super && (targeted? || enforce_rule!(current_user))
    end

    def resolve(**input)
      return complete(perform(**input), nil, input) unless targeted?

      # 見えない対象は存在しない対象と同じく NOT_FOUND にする（docs/architecture/graphql-schema.md「ID と `node`」）
      target = find_target(**input)
      return to_payload(OperationResult.failure(:not_found)) unless target

      enforce_rule!(target)
      complete(perform(target, **input), target, input)
    end

    private

    def targeted?
      respond_to?(:find_target, true)
    end

    # 成功したときだけ、要求のトランザクションの中で監査ログに 1 行を書く。失敗した公開 API は自分のセーブポイントまで戻している。
    # 監査の行の INSERT が失敗すれば例外になり、GraphqlController が要求ごと戻す
    def complete(result, target, input)
      record_audit(result.value, target, input) if result.success?
      to_payload(result)
    end

    def record_audit(result, target, input)
      declaration = self.class.audit_declaration or return

      arguments = { result:, target:, input: }
      value = instance_exec(**arguments, &declaration[:target])
      counterparty_tenant_id = declaration[:counterparty] && instance_exec(**arguments, &declaration[:counterparty])
      AuditLog.record_operation!(actor_user_id: current_user.user_id, action: declaration[:action],
        target_type: value.class.name.demodulize.delete_suffix("Value"), target_id: value.id, counterparty_tenant_id:)
    end

    def to_payload(result)
      return { errors: [] }.merge(self.class.result_field_name => result.value) if result.success?

      # 操作の終わりのログ（graphql.operation_completed）に、ユーザーエラーのコードを書く
      (context[:user_error_codes] ||= []).concat(result.failures.map { _1.code.to_s.upcase })
      errors = result.failures.map do |failure|
        {
          code: failure.code,
          message: failure.message || failure.code.to_s.humanize,
          path: failure.path&.map { |key| key.to_s.camelize(:lower) }
        }
      end
      { errors: }
    end
  end
end
