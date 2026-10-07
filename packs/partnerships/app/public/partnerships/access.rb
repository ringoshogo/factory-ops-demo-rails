module Partnerships
  # 「発注側の操作者は、受注側テナントに対して permission の操作をしてよいか」に答える
  # （docs/architecture/data-model.md「取引関係と権限付与」）。有効な取引関係と権限付与の両方が要る。
  # 存在しないテナントも、関係の無いテナント・失効したテナントと同じく偽になる
  module Access
    PERMISSIONS = PartnershipGrant::PERMISSIONS

    def self.permitted?(actor, supplier_tenant_id:, permission:)
      raise ArgumentError, "unknown permission: #{permission}" unless PERMISSIONS.include?(permission.to_s)

      Scope.call(actor, :as_buyer).where(owner_tenant_id: supplier_tenant_id)
        .joins(:grants).where(partnership_grants: { permission: permission.to_s }).exists?
    end
  end
end
