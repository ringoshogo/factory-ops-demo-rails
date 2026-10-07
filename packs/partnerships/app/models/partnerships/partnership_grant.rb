module Partnerships
  class PartnershipGrant < TenantRecord
    PERMISSIONS = %w[view_catalog place_orders view_shipments].freeze

    belongs_to :partnership, inverse_of: :grants
  end
end
