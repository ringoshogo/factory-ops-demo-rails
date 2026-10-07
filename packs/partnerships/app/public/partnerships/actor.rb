module Partnerships
  # 操作者。公開 API とリゾルバは、モデルではなくこの値を受け渡す。
  # partner_code は自社テナントの取引用コードで、受注側へ業務の外で伝えるために admin に見せる
  Actor = Data.define(:user_id, :tenant_id, :name, :email, :role, :partner_code) do
    def admin? = role == "admin"
  end
end
