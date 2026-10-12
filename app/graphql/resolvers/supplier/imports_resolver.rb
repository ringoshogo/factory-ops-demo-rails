module Resolvers
  module Supplier
    class ImportsResolver < BaseResolver
      perspective :supplier
      authorize_with Imports::ImportPolicy, :list?

      type Types::ImportType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Imports::Runs.list(current_user, first:, after:) }
      end
    end
  end
end
