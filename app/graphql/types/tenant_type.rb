module Types
  # どちらの視点からも、ID と名前だけを見せる
  class TenantType < BaseObject
    graphql_name "Tenant"
    perspective :shared
    authorization_exempt reason: "ID と名前だけの葉。認可済みの型のフィールドか、自社のテナントを返す viewer.tenant としてだけ現れる"

    field :id, ID, null: false
    field :name, String, null: false
  end
end
