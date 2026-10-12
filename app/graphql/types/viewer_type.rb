module Types
  # ログイン中のユーザー。Partnerships::Actor を包む
  class ViewerType < BaseObject
    graphql_name "Viewer"
    perspective :shared
    authorization_exempt reason: "ログイン中のユーザーと自社テナントだけを返す"

    field :id, ID, null: false, method: :user_id
    field :name, String, null: false
    field :email, String, null: false
    field :role, String, null: false
    field :partner_code, String, description: "自社テナントの取引用コード。受注側へ業務の外で伝えるもので、admin にだけ返す"
    field :tenant, TenantType, null: false, description: "自社テナント。取引用コードは含めない（partnerCode が admin にだけ返す）"
    field :audit_logs, resolver: Resolvers::Viewer::AuditLogsResolver, description: "admin だけ。新しいものから"

    def partner_code = object.admin? ? object.partner_code : nil

    def tenant = Partnerships::Directory.tenants(object, [ object.tenant_id ]).fetch(object.tenant_id)
  end
end
