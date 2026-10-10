module Fulfillment
  # 出荷依頼の状況を、出荷依頼の時刻列と出荷指示・出荷実績から優先順で導出する
  # （docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。
  # 出荷停止を記録する表（shipping_holds）が無いので、導出表の「出荷停止中」は導出しない
  module ShipmentRequestStatus
    def self.derive(request, instructed:, shipped:)
      if request.cancelled_at then :cancelled
      elsif shipped then :shipped
      elsif instructed then :instructed
      else :ready
      end
    end
  end
end
