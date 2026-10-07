module Types
  # どちらの視点からも、ID と名前だけを見せる
  class TenantType < BaseObject
    graphql_name "Tenant"
    perspective :shared
    authorization_exempt reason: "ID と名前だけの葉。認可済みの型のフィールドとしてだけ現れる"

    field :id, ID, null: false
    field :name, String, null: false
  end
end
