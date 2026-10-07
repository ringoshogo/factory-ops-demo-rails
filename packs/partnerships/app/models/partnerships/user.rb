module Partnerships
  class User < TenantRecord
    self.table_name = "users"

    has_secure_password
    normalizes :email, with: ->(email) { email.strip.downcase }
  end
end
