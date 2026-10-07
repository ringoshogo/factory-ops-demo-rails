module TenantHelpers
  def connection
    ActiveRecord::Base.lease_connection
  end

  # tenants は RLS を付けない表なので、テナントを設定せずに作れる
  def create_tenant(code)
    connection.select_value(<<~SQL)
      INSERT INTO tenants (code, name, partner_code, created_at, updated_at)
      VALUES (#{connection.quote(code)}, #{connection.quote(code)}, #{connection.quote("p-#{code}")}, now(), now())
      RETURNING id
    SQL
  end

  def insert_user(owner_tenant_id, email, password: "password")
    digest = BCrypt::Password.create(password, cost: BCrypt::Engine::MIN_COST)
    connection.select_value(<<~SQL)
      INSERT INTO users (owner_tenant_id, email, name, role, password_digest, created_at, updated_at)
      VALUES (#{connection.quote(owner_tenant_id)}, #{connection.quote(email)}, 'name', 'member', #{connection.quote(digest)}, now(), now())
      RETURNING id
    SQL
  end

  def tenant_setting
    connection.select_value("SELECT current_setting('app.tenant_id', true)")
  end
end
