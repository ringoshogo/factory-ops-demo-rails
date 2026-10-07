module Types
  # mutation は入れ子にせず、ここに並べる。視点と規則は各 mutation が宣言する
  class MutationType < BaseObject
    perspective :root
    authorization_exempt reason: "ルートの型。フィールドはすべて mutation で、各自が宣言する"

    field :establish_partnership, mutation: Mutations::EstablishPartnership
    field :revoke_partnership, mutation: Mutations::RevokePartnership
    field :grant_permission, mutation: Mutations::GrantPermission
    field :withdraw_permission, mutation: Mutations::WithdrawPermission
    field :save_item, mutation: Mutations::SaveItem
    field :set_item_published, mutation: Mutations::SetItemPublished
    field :register_part_mapping, mutation: Mutations::RegisterPartMapping
    field :allocate_sales_order, mutation: Mutations::AllocateSalesOrder
    field :adjust_stock, mutation: Mutations::AdjustStock
    field :place_purchase_order, mutation: Mutations::PlacePurchaseOrder
  end
end
