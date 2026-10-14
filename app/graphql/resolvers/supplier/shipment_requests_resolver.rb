module Resolvers
  module Supplier
    class ShipmentRequestsResolver < BaseResolver
      include SortArguments

      perspective :supplier
      authorize_with Fulfillment::ShipmentRequestPolicy, :list?

      type Types::ShipmentRequestType.connection_type, null: false
      sort_arguments Types::ShipmentRequestOrderType
      argument :filter, Types::ShipmentRequestFilterType, required: false

      def resolve(order_by: nil, then_by: nil, filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Fulfillment::ShipmentRequests.list(current_user, first:, after:, order_by: sort_list(order_by, then_by), filter: filter.to_h)
        end
      end
    end
  end
end
