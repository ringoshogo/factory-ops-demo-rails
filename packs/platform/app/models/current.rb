class Current < ActiveSupport::CurrentAttributes
  # tenant_id は Tenancy.with_tenant だけが設定する。直接代入すると DB の app.tenant_id と食い違う
  attribute :tenant_id, :actor
end
