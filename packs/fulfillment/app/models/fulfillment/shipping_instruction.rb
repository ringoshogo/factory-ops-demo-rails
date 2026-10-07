module Fulfillment
  # 出荷指示。有効（active）な指示は出荷依頼ごとに 1 件で、部分一意索引が守る
  class ShippingInstruction < TenantRecord
    STATUSES = %w[active cancelled].freeze

    belongs_to :shipment_request, inverse_of: :instructions

    validates :status, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active") }

    def active? = status == "active"
  end
end
