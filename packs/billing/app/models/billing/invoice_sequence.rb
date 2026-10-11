module Billing
  # 請求番号の採番行。テナントごとに 1 行（DocumentNumber）
  class InvoiceSequence < TenantRecord
  end
end
