module Sales
  # 受注番号の採番行。テナントごとに 1 行（DocumentNumber）
  class SalesOrderSequence < TenantRecord
  end
end
