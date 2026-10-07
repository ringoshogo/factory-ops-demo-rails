module Resolvers
  module Supplier
    class PartMappingsResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::PartMappingPolicy, :list?

      type Types::PartMappingType.connection_type, null: false
      argument :customer_tenant_id, ID, required: false

      def resolve(customer_tenant_id: nil)
        Connections::PagedQuery.new do |first:, after:|
          Sales::PartMappings.list(current_user, customer_tenant_id:, first:, after:)
        end
      end
    end
  end
end
