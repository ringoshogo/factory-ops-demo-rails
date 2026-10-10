module Types
  # 受注側が所有する取引先ごとの請求条件
  class BillingTermType < BaseObject
    graphql_name "BillingTerm"
    perspective :supplier
    authorize_with Billing::InvoicePolicy

    field :id, ID, null: false
    field :customer, TenantType, null: false
    field :closing_day, Int, null: false, description: "締め日。1〜28 か、月末を表す 31"

    def customer
      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user]).load(object.customer_tenant_id)
    end
  end
end
