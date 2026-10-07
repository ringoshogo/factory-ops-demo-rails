module Types
  # 経路 1。取引先が公開した品目。品目 ID は返さず、受注側テナントと品目コードで識別する
  class PublishedCatalogItemType < BaseObject
    graphql_name "PublishedCatalogItem"
    perspective :buyer
    cross_tenant_read :catalog
    authorize_with Sales::ItemPolicy, :show_to_buyer?

    field :code, String, null: false
    field :name, String, null: false
    field :unit, String, null: false
    field :unit_price, GraphQL::Types::BigInt, null: false
    field :tax_rate_percent, Int, null: false
  end
end
