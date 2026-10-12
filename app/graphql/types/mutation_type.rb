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
    field :schedule_item_price, mutation: Mutations::ScheduleItemPrice
    field :correct_item_price, mutation: Mutations::CorrectItemPrice
    field :register_part_mapping, mutation: Mutations::RegisterPartMapping
    field :allocate_sales_order, mutation: Mutations::AllocateSalesOrder
    field :cancel_sales_order, mutation: Mutations::CancelSalesOrder
    field :approve_cancellation_review, mutation: Mutations::ApproveCancellationReview
    field :reject_cancellation_review, mutation: Mutations::RejectCancellationReview
    field :adjust_stock, mutation: Mutations::AdjustStock
    field :create_shipping_instruction, mutation: Mutations::CreateShippingInstruction
    field :cancel_shipping_instruction, mutation: Mutations::CancelShippingInstruction
    field :post_shipment, mutation: Mutations::PostShipment
    field :set_billing_term, mutation: Mutations::SetBillingTerm
    field :close_billing_period, mutation: Mutations::CloseBillingPeriod
    field :discard_draft_invoice, mutation: Mutations::DiscardDraftInvoice
    field :issue_invoice, mutation: Mutations::IssueInvoice
    field :place_purchase_order, mutation: Mutations::PlacePurchaseOrder
    field :request_purchase_order_cancellation, mutation: Mutations::RequestPurchaseOrderCancellation
    field :inspect_inbound_shipment, mutation: Mutations::InspectInboundShipment
  end
end
