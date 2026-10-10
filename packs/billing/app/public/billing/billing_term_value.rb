module Billing
  # 請求条件の値。closing_day の 31 は月末を表す
  BillingTermValue = Data.define(:id, :owner_tenant_id, :customer_tenant_id, :closing_day)
end
