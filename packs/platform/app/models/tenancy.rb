# トランザクションのテナントを設定する（docs/architecture/data-model.md「RLS」）
module Tenancy
  class MissingTenant < StandardError; end
  class TenantMismatch < StandardError; end

  # トランザクションを開き、SET LOCAL app.tenant_id と Current.tenant_id を設定してブロックを実行する。
  # 入れ子では外側のテナントをそのまま使い、別のテナントへの切り替えは例外にする
  def self.with_tenant(tenant_id, &block)
    raise ArgumentError, "tenant_id is blank" if tenant_id.blank?

    if Current.tenant_id.present?
      if Current.tenant_id.to_s != tenant_id.to_s
        raise TenantMismatch, "Tenancy.with_tenant の中で別のテナントに切り替えようとした"
      end

      return ApplicationRecord.transaction(requires_new: true, &block)
    end

    ApplicationRecord.with_connection do |connection|
      connection.transaction(requires_new: true) do
        set_tenant_id(connection, tenant_id, local: true)
        Current.set(tenant_id: tenant_id, &block)
      end
    ensure
      # 外側にトランザクションがあると（テストなど）、SET LOCAL はその終わりまで残る。
      # セッションの値は、誰かが SET で残すとトランザクションの後に現れる。どちらも次の利用者に漏れるので、セッションの値ごと空にする
      reset!(connection)
    end
  end

  def self.require_tenant!
    raise MissingTenant, "Tenancy.with_tenant の外でテナントの表を使った" if Current.tenant_id.blank?
  end

  # 接続のセッションの app.tenant_id を空にする。接続を貸し出すたびにも呼ぶ（config/initializers/tenancy.rb）
  def self.reset!(connection)
    set_tenant_id(connection, "", local: false)
  end

  def self.set_tenant_id(connection, value, local:)
    connection.exec_query("SELECT set_config('app.tenant_id', $1, $2)", "Tenancy", [ value, local ])
  end
  private_class_method :set_tenant_id
end
