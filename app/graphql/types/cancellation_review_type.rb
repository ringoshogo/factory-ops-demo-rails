module Types
  # 受注側が所有する取消の審査。連結元の取消依頼 ID は相手側を指すので、フィールドに出さない
  class CancellationReviewType < BaseObject
    graphql_name "CancellationReview"
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy

    field :id, ID, null: false
    field :requested_at, GraphQL::Types::ISO8601DateTime, null: false, description: "発注側が取消依頼を登録した時刻"
    field :decision, CancellationOutcomeType, description: "審査中は空"
    field :decided_at, GraphQL::Types::ISO8601DateTime, description: "審査中は空"
  end
end
