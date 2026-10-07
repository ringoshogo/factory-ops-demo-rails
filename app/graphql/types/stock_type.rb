module Types
  # 受注側が所有する品目ごとの在庫。available は有効在庫（現在庫 - 引当）
  class StockType < BaseObject
    graphql_name "Stock"
    perspective :supplier
    authorize_with Inventory::StockPolicy

    field :item, ItemType, null: false
    field :on_hand, Int, null: false
    field :allocated, Int, null: false
    field :available, Int, null: false
    field :safety_stock, Int, null: false
    field :below_safety_stock, Boolean, null: false

    def item
      dataloader.with(Sources::PublicApiSource, Sales::Catalog, :items_for, context[:current_user]).load(object.item_id)
    end
  end
end
