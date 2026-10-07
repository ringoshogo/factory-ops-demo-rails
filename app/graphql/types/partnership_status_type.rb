module Types
  class PartnershipStatusType < BaseEnum
    graphql_name "PartnershipStatus"

    value "ACTIVE", value: "active"
    value "REVOKED", value: "revoked"
  end
end
