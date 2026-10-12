module Types
  # 視点と認可は中身の型の宣言に従う
  class BaseConnection < BaseObject
    include GraphQL::Types::Relay::ConnectionBehaviors

    # ConnectionBehaviors が足す GraphQL::Types::Relay::PageInfo は宣言を持たないので差し替える
    own_fields.delete("pageInfo")
    field :page_info, PageInfoType, null: false
    field :total_count, Integer, null: false,
      description: "絞り込んだ一覧の行の数。first と after によらない。選んだときだけ数える"

    def total_count = object.total_count

    class << self
      def perspective(value = nil)
        value.nil? ? node_type&.perspective : super
      end

      def authorization_exempt_reason = "中身の型が宣言を持つ"
    end
  end
end
