module Types
  # mutation の戻り値の型。視点は mutation の宣言に従い、認可は中身の型の宣言に従う
  class BasePayload < BaseObject
    class << self
      def perspective(value = nil)
        value.nil? ? mutation&.perspective : super
      end

      def authorization_exempt_reason = "中身の型が宣言を持つ"
    end
  end
end
