module Types
  class PurchaseOrderLineInputType < BaseInputObject
    graphql_name "PurchaseOrderLineInput"

    argument :part_number, String, description: "発注側の自社品番"
    argument :quantity, Int
  end
end
