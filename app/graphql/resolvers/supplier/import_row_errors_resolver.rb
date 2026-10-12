module Resolvers
  module Supplier
    # 取り込みの失敗した行
    class ImportRowErrorsResolver < BaseResolver
      perspective :supplier
      authorize_with Imports::ImportPolicy, :list?

      type Types::ImportRowErrorType.connection_type, null: false

      def resolve
        Connections::PagedQuery.new { |first:, after:| Imports::Runs.row_errors(current_user, object.id, first:, after:) }
      end
    end
  end
end
