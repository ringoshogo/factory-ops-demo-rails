# トランザクションのテナントを設定する（docs/architecture/data-model.md「RLS」）
module Tenancy
  class MissingTenant < StandardError; end

  # トランザクションを開き、SET LOCAL app.tenant_id と Current.tenant_id を設定してブロックを実行する
  def self.with_tenant(tenant_id, &block)
    raise ArgumentError, "tenant_id is blank" if tenant_id.blank?

    ApplicationRecord.transaction(requires_new: true) do
      set_tenant_id(tenant_id)
      Current.set(tenant_id: tenant_id, &block)
    end
  ensure
    # 外側にトランザクションがあると（テストなど）、SET LOCAL はその終わりまで残り、後の操作に前のテナントが漏れる。
    # セーブポイントを巻き戻した場合は PostgreSQL が値を戻すので、ここで空にするのはコミットした場合のため
    set_tenant_id("")
  end

  def self.require_tenant!
    raise MissingTenant, "Tenancy.with_tenant の外でテナントの表を使った" if Current.tenant_id.blank?
  end

  def self.set_tenant_id(value)
    ApplicationRecord.with_connection { |c| c.exec_query("SELECT set_config('app.tenant_id', $1, true)", "Tenancy", [ value ]) }
  end
  private_class_method :set_tenant_id
end
