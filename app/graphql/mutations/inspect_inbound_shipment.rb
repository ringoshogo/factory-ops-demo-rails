module Mutations
  # 自社の入荷を、全明細の検収数量で 1 回だけ検収し、「検収完了」を出す。入力の誤りは INVALID_INPUT、2 回目は CONFLICT
  class InspectInboundShipment < BaseMutation
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy, :inspect_receipt?
    # 成功の値は発注なので、相手は発注の受注側から取る
    audit "inbound_shipment.inspect", target: ->(target:, **) { target }, counterparty: ->(result:, **) { result.supplier_tenant_id }

    argument :inbound_shipment_id, ID
    argument :lines, [ Types::ReceiptInspectionLineInputType ]
    result_field :purchase_order, Types::PurchaseOrderType

    # 自社の入荷だけを引く。見えない ID は NOT_FOUND になる
    def find_target(inbound_shipment_id:, **)
      Purchasing::PurchaseOrders.find_inbound_shipment(current_user, inbound_shipment_id)
    end

    def perform(target, lines:, **)
      Purchasing::ReceiptInspections.record(current_user, inbound_shipment_id: target.id, lines: lines.map(&:to_h))
    end
  end
end
