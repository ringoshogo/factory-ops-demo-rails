module Resolvers
  module Supplier
    # 見えない ID は存在しない ID と同じく null
    class ImportResolver < BaseResolver
      perspective :supplier
      authorize_with Imports::ImportPolicy, :list?

      type Types::ImportType, null: true
      argument :id, ID

      def resolve(id:) = Imports::Runs.find(current_user, id)
    end
  end
end
