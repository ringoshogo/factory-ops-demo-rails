module Resolvers
  module Buyer
    # 経路 3。view_shipments の付与が無ければ空
    class SupplierShipmentsResolver < BaseResolver
      perspective :buyer
      authorize_with Fulfillment::ShipmentRequestPolicy, :list?

      type [ Types::SupplierShipmentType ], null: false

      def resolve
        dataloader.with(Sources::PublicApiSource, Fulfillment::PartnerShipments, :for_purchase_orders, current_user).load(object.id)
      end
    end
  end
end
