module Types
  class UserErrorCodeType < BaseEnum
    graphql_name "UserErrorCode"

    value "INVALID_INPUT", "形式や範囲の誤り", value: :invalid_input
    value "NOT_FOUND", "存在しないか、見えない ID", value: :not_found
    value "NOT_PERMITTED", "権限付与が無い、取引関係が無いか失効している", value: :not_permitted
    value "CONFLICT", "状態と両立しない", value: :conflict
  end
end
