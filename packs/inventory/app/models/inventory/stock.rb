module Inventory
  # 品目ごとの在庫。on_hand・allocated を変えるのは move! だけで、変えるたびに在庫移動履歴を 1 行足す
  # （docs/architecture/data-model.md「在庫」）。有効在庫が負にならないことは DB の CHECK 制約が守る
  class Stock < TenantRecord
    # 移動の種類ごとの、on_hand と allocated の増減の向き
    EFFECTS = {
      "inbound" => [ 1, 0 ],
      "outbound" => [ -1, 0 ],
      "allocate" => [ 0, 1 ],
      "deallocate" => [ 0, -1 ],
      "ship" => [ -1, -1 ]
    }.freeze

    # 品目ごとの在庫の行を、無ければ数量 0 で作り、item_id の昇順に行ロックして返す
    # （docs/architecture/data-model.md「取消と出荷の競合を止める場所」のロックの順）
    def self.lock_for(owner_tenant_id, item_ids)
      stocks = where(owner_tenant_id:, item_id: item_ids.uniq)
      missing = item_ids.uniq - stocks.pluck(:item_id)
      insert_all(missing.map { { owner_tenant_id:, item_id: _1 } }, unique_by: %i[owner_tenant_id item_id]) if missing.any?
      stocks.order(:item_id).lock.index_by(&:item_id)
    end

    def available = on_hand - allocated

    # 在庫を変える唯一の入口。呼ぶ側がこの行をロックしてから呼ぶ
    def move!(type, quantity, reason: nil, allocation: nil)
      on_hand_sign, allocated_sign = EFFECTS.fetch(type)
      @moving = true
      update!(on_hand: on_hand + on_hand_sign * quantity, allocated: allocated + allocated_sign * quantity)
      StockMovement.create!(owner_tenant_id:, item_id:, type:, quantity:, reason:, allocation:)
    ensure
      @moving = false
    end

    # move! を通らない数量の書き換えを止める
    def readonly? = (persisted? && !@moving) || super
  end
end
