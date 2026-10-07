module Resolvers
  module Supplier
    class ShipmentRequestsResolver < BaseResolver
      perspective :supplier
      authorize_with Fulfillment::ShipmentRequestPolicy, :list?

      type Types::ShipmentRequestType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Fulfillment::ShipmentRequests.list(current_user, first:, after:) }
      end
    end
  end
end
