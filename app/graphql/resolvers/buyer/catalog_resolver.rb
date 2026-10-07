module Resolvers
  module Buyer
    # 経路 1。view_catalog の付与が無ければ空
    class CatalogResolver < BaseResolver
      perspective :buyer
      authorize_with Sales::ItemPolicy, :list?

      type Types::PublishedCatalogItemType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new do |first:, after:|
          Sales::PublishedCatalog.items(current_user, supplier_tenant_id: object.supplier.id, first:, after:)
        end
      end
    end
  end
end
