module Platform
  # 自社の監査ログを、新しいものから読む（docs/architecture/graphql-schema.md「読み取りの一覧」）。
  # filter は action・correlation_id の一致と、occurred_from 以上・occurred_to 未満の時刻で絞る
  module AuditLogs
    def self.list(actor, first:, after:, filter: {})
      Page.of(filtered(scope(actor), **filter), first:, after:) { |rows| rows.map { to_value(_1) } }
    end

    def self.filtered(relation, action: nil, correlation_id: nil, occurred_from: nil, occurred_to: nil)
      relation = relation.where(action:) if action
      relation = relation.where(correlation_id:) if correlation_id
      relation = relation.where(occurred_at: occurred_from..) if occurred_from
      relation = relation.where(occurred_at: ...occurred_to) if occurred_to
      relation
    end

    def self.scope(actor)
      AuditLogPolicy.new(user: actor).apply_scope(AuditLog.all, type: :active_record_relation, name: :own)
    end

    def self.to_value(row) = AuditLogValue.new(**row.slice(*AuditLogValue.members.map(&:to_s)).symbolize_keys)
    private_class_method :filtered, :scope, :to_value
  end
end
