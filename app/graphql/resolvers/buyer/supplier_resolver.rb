module Resolvers
  module Buyer
    # 経路 2 の取引先を 1 社選ぶ。取引関係の無い相手・失効した相手・存在しないテナントは区別せず null
    class SupplierResolver < BaseResolver
      perspective :buyer
      authorize_with Partnerships::PartnershipPolicy, :list?

      type Types::SupplierPartnershipType, null: true
      argument :supplier_tenant_id, ID

      def resolve(supplier_tenant_id:) = Partnerships::Directory.for_buyer_supplier(current_user, supplier_tenant_id)
    end
  end
end
