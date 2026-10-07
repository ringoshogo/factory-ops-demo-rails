module Purchasing
  # 発注の状況を、発注の時刻列と購買の中の入荷・検収から優先順で導出する
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # 入荷（M14）と検収（M17）の有無は、呼ぶ側が購買の表から求めて渡す
  module PurchaseOrderStatus
    def self.derive(order, inbound: false, inspected: false)
      if order.supplier_cancelled_at then :supplier_cancelled
      elsif order.cancelled_at then :cancelled
      elsif inspected then :inspected
      elsif inbound then :inbound
      elsif order.accepted_at then :accepted
      elsif order.awaiting_match_at then :awaiting_supplier_confirmation
      else :sent
      end
    end
  end
end
