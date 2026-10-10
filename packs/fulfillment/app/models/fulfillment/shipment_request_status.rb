module Fulfillment
  # 出荷依頼の状況を、出荷依頼の時刻列と、出荷停止・出荷指示・出荷実績から優先順で導出する
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # held は同じ受注に解除されていない出荷停止があるかで、呼ぶ側が出荷停止の表から求めて渡す
  module ShipmentRequestStatus
    def self.derive(request, instructed:, shipped:, held:)
      if request.cancelled_at then :cancelled
      elsif shipped then :shipped
      elsif held then :on_hold
      elsif instructed then :instructed
      else :ready
      end
    end
  end
end
