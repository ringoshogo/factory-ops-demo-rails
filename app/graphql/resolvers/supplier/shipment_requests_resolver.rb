module Resolvers
  module Supplier
    class ShipmentRequestsResolver < BaseResolver
      perspective :supplier
      authorize_with Fulfillment::ShipmentRequestPolicy, :list?

      type Types::ShipmentRequestType.connection_type, null: false
      argument :order_by, Types::ShipmentRequestOrderType, required: false
      argument :filter, Types::ShipmentRequestFilterType, required: false

      def resolve(order_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Fulfillment::ShipmentRequests.list(current_user, first:, after:, order_by: order_by&.to_h, filter: filter.to_h)
        end
      end
    end
  end
end
