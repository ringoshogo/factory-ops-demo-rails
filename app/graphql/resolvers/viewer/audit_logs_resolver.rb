module Resolvers
  module Viewer
    # 自社の監査ログを新しいものから返す。admin だけが読み、member には FORBIDDEN を返す
    class AuditLogsResolver < BaseResolver
      perspective :shared
      authorize_with Platform::AuditLogPolicy, :index?

      type Types::AuditLogType.connection_type, null: false
      argument :filter, Types::AuditLogFilterType, required: false

      def resolve(filter: nil)
        Connections::PagedQuery.new do |first:, after:|
          Platform::AuditLogs.list(current_user, filter: filter.to_h, first:, after:)
        end
      end
    end
  end
end
