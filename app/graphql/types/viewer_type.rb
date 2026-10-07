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
  end
end
