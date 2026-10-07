module Partnerships
  # owner_tenant_id が受注側、buyer_tenant_id が発注側
  class Partnership < TenantRecord
    has_many :grants, class_name: "Partnerships::PartnershipGrant", inverse_of: :partnership

    scope :active, -> { where(status: "active") }

    def active? = status == "active"
  end
end
