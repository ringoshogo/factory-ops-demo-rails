module Billing
  # 請求条件。customer_tenant_id は相手テナントへの ID 参照で、関連を張らない。closing_day の 31 は月末を表す
  class BillingTerm < TenantRecord
    MONTH_END = 31

    # 締め日の date が、この条件の締め日に当たるか
    def closing_date?(date) = closing_day == MONTH_END ? date == date.end_of_month : date.day == closing_day
  end
end
