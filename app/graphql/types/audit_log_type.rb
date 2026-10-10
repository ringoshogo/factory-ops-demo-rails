module Types
  # 自社の監査ログの 1 行。伝票の型へのフィールドを持たず、対象を型の名前と ID の文字列で示す
  # （docs/architecture/graphql-schema.md「監査ログ」）
  class AuditLogType < BaseObject
    graphql_name "AuditLog"
    perspective :shared
    authorize_with Platform::AuditLogPolicy

    field :occurred_at, GraphQL::Types::ISO8601DateTime, null: false
    field :action, String, null: false
    field :actor_name, String, description: "ユーザーの名前。イベントの受信は空"
    field :target_type, String, null: false
    field :target_id, ID, null: false
    field :counterparty, TenantType
    field :correlation_id, String, null: false, description: "運用者に問い合わせるときに伝える値"

    def actor_name
      return unless object.actor_user_id

      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :user_names, context[:current_user]).load(object.actor_user_id)
    end

    def counterparty
      return unless object.counterparty_tenant_id

      dataloader.with(Sources::PublicApiSource, Partnerships::Directory, :tenants, context[:current_user])
        .load(object.counterparty_tenant_id)
    end
  end
end
