# 監査ログの 1 行（docs/architecture/data-model.md「監査ログ（`platform`）」）。追記だけで、アプリのロールの書き換えと削除は
# DB の権限が、所有ロールの書き換えと削除はトリガーが拒む。書くのは mutation の基底クラスとイベントのジョブの基底クラスだけで、
# 操作の中で手書きしない（docs/architecture/graphql-schema.md「監査ログ」）
class AuditLog < TenantRecord
  def readonly? = persisted?

  # 利用者の操作を 1 行書く。要求 ID と相関 ID は、いまの Rails.event の文脈から取る
  def self.record_operation!(actor_user_id:, action:, target_type:, target_id:, counterparty_tenant_id:)
    context = Rails.event.context
    write!(actor_type: "user", actor_user_id:, action:, target_type:, target_id:, counterparty_tenant_id:,
      request_id: context[:request_id], correlation_id: context[:correlation_id], causation_id: context[:causation_id])
  end

  # 相手テナントが発行したイベントの受信を 1 行書く。同じイベントの 2 回目の配送では、一意索引に当たって何もしない
  def self.record_receipt!(event_id:, event_name:, source_tenant_id:, correlation_id:)
    Tenancy.require_tenant!
    insert(row(actor_type: "system", action: "event.received", target_type: event_name.demodulize, target_id: event_id,
      counterparty_tenant_id: source_tenant_id, correlation_id:, causation_id: event_id), unique_by: :index_audit_logs_on_event_receipt)
  end

  def self.write!(**attributes)
    Tenancy.require_tenant!
    insert!(row(**attributes))
  end

  def self.row(**attributes) = { owner_tenant_id: Current.tenant_id, **attributes }
  private_class_method :write!, :row
end
