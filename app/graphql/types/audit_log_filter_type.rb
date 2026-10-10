module Types
  # 監査ログの絞り込み。時刻は occurredFrom 以上・occurredTo 未満
  class AuditLogFilterType < BaseInputObject
    graphql_name "AuditLogFilter"

    argument :action, String, required: false
    argument :correlation_id, String, required: false
    argument :occurred_from, GraphQL::Types::ISO8601DateTime, required: false
    argument :occurred_to, GraphQL::Types::ISO8601DateTime, required: false
  end
end
