module Mutations
  # mutation は perspective と authorize_with <Policy>, :<規則> を宣言し、perform で公開 API を呼んで OperationResult を返す。
  # 対象を引く mutation は find_target を定義する。規則は対象を引いた後に対象に対して、作成系は操作者に対して評価する
  class BaseMutation < GraphQL::Schema::Mutation
    include GraphQL::Schema::HasSingleInputArgument
    # action_policy-graphql は field_class に拡張を prepend するので、GraphQL::Schema::Field に入らないよう先に差し替える
    field_class Types::BaseField
    object_class Types::BasePayload
    include ActionPolicy::GraphQL::Behaviour
    include AuthorizationDeclarations

    field :errors, [ Types::UserErrorType ], null: false

    # 成功したときに値を返すフィールド。失敗したときは空になる
    def self.result_field(name, type)
      field name, type
      @result_field_name = name
    end

    class << self
      attr_reader :result_field_name
    end

    def authorized?(**inputs)
      self.class.check_declarations!
      super && (targeted? || enforce_rule!(current_user))
    end

    def resolve(**input)
      return to_payload(perform(**input)) unless targeted?

      # 見えない対象は存在しない対象と同じく NOT_FOUND にする（docs/architecture/graphql-schema.md「ID と `node`」）
      target = find_target(**input)
      return to_payload(OperationResult.failure(:not_found)) unless target

      enforce_rule!(target)
      to_payload(perform(target, **input))
    end

    private

    def targeted?
      respond_to?(:find_target, true)
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
