module Platform
  # 監査ログの 1 行の値。metadata と要求 ID・因果 ID は運用者が DB で引くもので、画面には返さない
  AuditLogValue = Data.define(:id, :owner_tenant_id, :occurred_at, :action, :actor_user_id, :target_type, :target_id,
    :counterparty_tenant_id, :correlation_id)
end
