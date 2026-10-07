module Types
  # 受注側が所有する取引関係。失効したものも含む
  class PartnershipType < BaseObject
    graphql_name "Partnership"
    perspective :supplier
    authorize_with Partnerships::PartnershipPolicy

    field :id, ID, null: false
    field :buyer, TenantType, null: false
    field :status, PartnershipStatusType, null: false
    field :revoked_at, GraphQL::Types::ISO8601DateTime
    field :permissions, [ PartnershipPermissionType ], null: false
  end
end
