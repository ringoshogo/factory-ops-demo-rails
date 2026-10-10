class CreateAuditLogs < ActiveRecord::Migration[8.1]
  include TenantTable

  # 監査ログ（docs/architecture/data-model.md「監査ログ（`platform`）」）。actor_user_id と counterparty_tenant_id は
  # 外部キーを張らない ID 参照。アプリのロールの UPDATE・DELETE は lib/tasks/db_roles.rake が権限で止める
  def change
    create_tenant_table :audit_logs, comment: "[基盤] 監査ログ。相手テナントに効果が及ぶ書き込みを 1 行ずつ追記し、書き換えない" do |t|
      t.datetime :occurred_at, null: false, default: -> { "now()" }
      t.string :actor_type, null: false
      t.uuid :actor_user_id
      t.string :action, null: false
      t.string :target_type, null: false
      t.uuid :target_id, null: false
      t.uuid :counterparty_tenant_id
      t.string :request_id
      t.string :correlation_id, null: false
      t.uuid :causation_id
      t.jsonb :metadata, null: false, default: {}

      t.index [ :owner_tenant_id, :correlation_id ]
      # イベントの受信の冪等キー。同じイベントの 2 回目の配送で増えない
      t.index [ :owner_tenant_id, :causation_id, :action ], unique: true, where: "action = 'event.received'",
        name: "index_audit_logs_on_event_receipt"
      t.check_constraint "actor_type::text IN ('user', 'system')", name: "audit_logs_actor_type_check"
      t.check_constraint "(actor_type = 'user') = (actor_user_id IS NOT NULL)", name: "audit_logs_actor_user_check"
    end

    reversible do |dir|
      dir.up do
        safety_assured do
          # 保存期間は 7 年。トリガーと purge_expired_audit_logs は同じ期間を使う
          execute <<~SQL
            CREATE FUNCTION audit_logs_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN
              IF TG_OP = 'UPDATE' THEN
                RAISE EXCEPTION 'audit_logs は書き換えられない';
              ELSIF TG_OP = 'TRUNCATE' THEN
                RAISE EXCEPTION 'audit_logs は TRUNCATE できない';
              ELSIF OLD.occurred_at >= now() - interval '7 years' THEN
                RAISE EXCEPTION '保存期間の中の audit_logs の行は消せない';
              END IF;
              RETURN OLD;
            END
            $$;

            CREATE TRIGGER audit_logs_append_only BEFORE UPDATE OR DELETE ON audit_logs
              FOR EACH ROW EXECUTE FUNCTION audit_logs_append_only();
            -- 行のトリガーは TRUNCATE で動かないので、文のトリガーで止める
            CREATE TRIGGER audit_logs_no_truncate BEFORE TRUNCATE ON audit_logs
              FOR EACH STATEMENT EXECUTE FUNCTION audit_logs_append_only();

            -- 所有ロールの rake タスク audit:purge が呼ぶ。消した行の数を返す
            CREATE FUNCTION purge_expired_audit_logs() RETURNS bigint LANGUAGE sql AS $$
              WITH deleted AS (DELETE FROM audit_logs WHERE occurred_at < now() - interval '7 years' RETURNING 1)
              SELECT count(*) FROM deleted
            $$;
          SQL
        end
      end
      dir.down do
        safety_assured do
          execute <<~SQL
            DROP TRIGGER audit_logs_no_truncate ON audit_logs;
            DROP TRIGGER audit_logs_append_only ON audit_logs;
            DROP FUNCTION audit_logs_append_only();
            DROP FUNCTION purge_expired_audit_logs();
          SQL
        end
      end
    end
  end
end
