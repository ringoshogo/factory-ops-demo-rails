module Types
  # 視点と認可は中身の型の宣言に従う
  class BaseEdge < BaseObject
    include GraphQL::Types::Relay::EdgeBehaviors

    class << self
      def perspective(value = nil)
        value.nil? ? node_type&.perspective : super
      end

      def authorization_exempt_reason = "中身の型が宣言を持つ"
    end
  end
end
