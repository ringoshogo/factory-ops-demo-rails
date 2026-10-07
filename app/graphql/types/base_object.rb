module Types
  # 型は perspective と、authorize_with か authorization_exempt のどちらかを宣言する
  class BaseObject < GraphQL::Schema::Object
    include AuthorizationDeclarations

    # 発注側の型のうち、相手テナントのデータを返す型が宣言する読む経路（docs/architecture/context-map.md「テナントと所有」）
    CROSS_TENANT_READS = %i[catalog partnerships shipments].freeze

    field_class BaseField

    class << self
      # 規則の既定は show?。同じ policy の値を別の視点の型で見せるときは、その視点の規則を渡す
      def authorize_with(policy, rule = :show?)
        super
      end

      def authorization_exempt(reason:)
        @authorization_exempt_reason = reason
      end

      def authorization_exempt_reason = @authorization_exempt_reason

      def authorization_declared?
        super || authorization_exempt_reason.present?
      end

      def cross_tenant_read(route = nil)
        return @cross_tenant_read if route.nil?
        raise ArgumentError, "unknown route: #{route}" unless CROSS_TENANT_READS.include?(route)

        @cross_tenant_read = route
      end

      # 返すオブジェクトごとに policy の規則を評価する。偽はスキーマの unauthorized_object で FORBIDDEN になる
      def authorized?(object, context)
        check_declarations!
        return false unless super
        return true if authorization_exempt_reason

        authorization_policy.new(object, user: context[:current_user], request_memo: context[:request_memo] ||= {})
          .apply(authorization_rule)
      end
    end

    # 両クラスはこのクラスを継承するので、上の定義を終えてから読み込む
    connection_type_class BaseConnection
    edge_type_class BaseEdge
  end
end
