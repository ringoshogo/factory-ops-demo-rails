module Types
  # 得意先品番の対応表の 1 行。受注側だけが所有し、発注側からは見えない
  class PartMappingType < BaseObject
    graphql_name "PartMapping"
    perspective :supplier
    authorize_with Sales::PartMappingPolicy

    field :id, ID, null: false
    field :customer, TenantType, null: false
    field :customer_part_number, String, null: false
    field :item, ItemType, null: false

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.customer_tenant_id)
    end

    def item
      dataloader.with(Sources::PublicApiSource, Sales::Catalog, :items_for, context[:current_user]).load(object.item_id)
    end
  end
end
