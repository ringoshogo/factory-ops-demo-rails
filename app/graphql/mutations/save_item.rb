module Mutations
  # 品目コードで自社の品目を引き、無ければ作り、あれば更新する。作った品目は公開しない
  class SaveItem < BaseMutation
    perspective :supplier
    authorize_with Sales::ItemPolicy, :save?

    argument :code, String
    argument :name, String
    argument :unit, String
    argument :unit_price, GraphQL::Types::BigInt
    argument :tax_rate_percent, Int, required: false, default_value: 10
    result_field :item, Types::ItemType

    def perform(**input)
      Sales::Catalog.save(current_user, **input)
    end
  end
end
