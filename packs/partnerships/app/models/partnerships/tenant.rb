module Partnerships
  # tenants は RLS を付けない表なので TenantRecord を継承しない。アプリのロールは読みと追加だけができる
  class Tenant < ApplicationRecord
    self.table_name = "tenants"
  end
end
