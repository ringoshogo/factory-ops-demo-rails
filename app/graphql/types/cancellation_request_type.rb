module Types
  # 発注側が所有する取消依頼。受注側の審査へたどるフィールドは持たず、還流した回答だけを見せる
  class CancellationRequestType < BaseObject
    graphql_name "CancellationRequest"
    perspective :buyer
    authorize_with Purchasing::PurchaseOrderPolicy

    field :id, ID, null: false
    field :reason, String, null: false
    field :outcome, CancellationOutcomeType, description: "回答待ちは空"
    field :decided_at, GraphQL::Types::ISO8601DateTime, description: "回答が届いた時刻。回答待ちは空"
  end
end
