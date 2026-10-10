class PinPurgeExpiredAuditLogsSearchPath < ActiveRecord::Migration[8.1]
  # 保存期間を過ぎた監査ログを消す関数（docs/architecture/data-model.md「監査ログ（`platform`）」）が、呼び出し元の
  # search_path に従って同じ名前の別の表（一時表など）を消さないよう、表をスキーマで修飾し、search_path を固定する
  def up
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION purge_expired_audit_logs() RETURNS bigint LANGUAGE sql
        SET search_path = pg_catalog, pg_temp AS $$
          WITH deleted AS (DELETE FROM public.audit_logs WHERE occurred_at < now() - interval '7 years' RETURNING 1)
          SELECT count(*) FROM deleted
        $$;
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION purge_expired_audit_logs() RETURNS bigint LANGUAGE sql
        RESET search_path AS $$
          WITH deleted AS (DELETE FROM audit_logs WHERE occurred_at < now() - interval '7 years' RETURNING 1)
          SELECT count(*) FROM deleted
        $$;
      SQL
    end
  end
end
