module Types
  class UserErrorType < BaseObject
    graphql_name "UserError"
    perspective :shared
    authorization_exempt reason: "データを持たない"

    field :code, UserErrorCodeType, null: false
    field :message, String, null: false
    field :path, [ String ], description: "入力のどこが原因か。入力全体なら空"
  end
end
