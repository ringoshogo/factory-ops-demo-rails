module Types
  class PartnershipPermissionType < BaseEnum
    graphql_name "PartnershipPermission"

    value "VIEW_CATALOG", "経路 1（カタログ）を開く", value: "view_catalog"
    value "PLACE_ORDERS", "発注を登録できる", value: "place_orders"
    value "VIEW_SHIPMENTS", "経路 3（自社の発注に連結した出荷）を開く", value: "view_shipments"
  end
end
