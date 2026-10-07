module Types
  class PurchaseOrderLineType < BaseObject
    graphql_name "PurchaseOrderLine"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :part_number, String, null: false
    field :quantity, Int, null: false
    field :confirmed_item_name, String, description: "受注確定で写した値。確定前は空"
    field :confirmed_unit_price, GraphQL::Types::BigInt, description: "受注確定で写した値。確定前は空"
  end
end
