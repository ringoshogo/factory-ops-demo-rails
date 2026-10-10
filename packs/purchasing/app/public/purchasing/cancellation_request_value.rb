module Purchasing
  # 取消依頼の値。outcome は :approved・:rejected の記号か、回答待ちなら空
  CancellationRequestValue = Data.define(:id, :owner_tenant_id, :purchase_order_id, :reason, :outcome, :decided_at)
end
