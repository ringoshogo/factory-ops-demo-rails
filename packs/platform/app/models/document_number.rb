# 伝票番号の採番（docs/architecture/data-model.md「テナントの持ち方」）。採番の表は各コンテキストが持ち、
# テナントごとの 1 行を行ロックして last_number を進める。行が無ければ作る。同じテナントの採番は行ロックで直列になる
module DocumentNumber
  def self.next(sequence_model, prefix:)
    Tenancy.require_tenant!
    number = sequence_model.connection.select_value(<<~SQL, "DocumentNumber", [ Current.tenant_id ])
      INSERT INTO #{sequence_model.quoted_table_name} AS s (owner_tenant_id, last_number, created_at, updated_at)
      VALUES ($1, 1, now(), now())
      ON CONFLICT (owner_tenant_id) DO UPDATE SET last_number = s.last_number + 1, updated_at = now()
      RETURNING last_number
    SQL
    format("%s-%06d", prefix, number)
  end
end
