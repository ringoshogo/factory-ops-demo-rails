module Partnerships
  # 受注側が取引関係を結び、失効させ、権限を付与・撤回する。役割の判定は PartnershipPolicy の規則で、呼び出す側が行う
  module Management
    # 相手は発注側テナントの取引用コードで指定する。テナントの code は推測できるので受け付けない
    # （docs/architecture/graphql-schema.md「ID と `node`」）
    def self.establish(actor, partner_code:)
      buyer = Tenant.find_by(partner_code: partner_code.to_s)
      return OperationResult.failure(:not_found, path: [ :partner_code ]) unless buyer
      return OperationResult.failure(:invalid_input, path: [ :partner_code ]) if buyer.id == actor.tenant_id

      # 有効な関係の重複は一意索引が拒否する。セーブポイントまで戻してから失敗を返す
      partnership = Partnership.transaction(requires_new: true) do
        Partnership.create!(owner_tenant_id: actor.tenant_id, buyer_tenant_id: buyer.id)
      end
      OperationResult.success(Directory.partnership(actor, partnership.id))
    rescue ActiveRecord::RecordNotUnique
      OperationResult.failure(:conflict, path: [ :partner_code ])
    end

    # 失効させた関係は再び有効にしない。取引を再開するときは establish で新しい関係を結ぶ
    def self.revoke(actor, partnership_id:)
      with_active_partnership(actor, partnership_id) do |partnership|
        partnership.update!(status: "revoked", revoked_at: Time.current)
      end
    end

    # 付与済みの権限の付与と、付与していない権限の撤回は、何もせず成功にする
    def self.grant(actor, partnership_id:, permission:)
      with_active_partnership(actor, partnership_id) do |partnership|
        partnership.grants.find_or_create_by!(owner_tenant_id: partnership.owner_tenant_id, permission: permission!(permission))
      end
    end

    def self.withdraw(actor, partnership_id:, permission:)
      with_active_partnership(actor, partnership_id) do |partnership|
        partnership.grants.where(permission: permission!(permission)).delete_all
      end
    end

    # 自社が受注側の関係を引き、組のロックと行ロックを取ってから、有効なときだけブロックを実行する。
    # 組のロックは、権限を確かめてから書く操作（発注の登録）と失効・撤回を直列にする（Access.lock_pair!）
    def self.with_active_partnership(actor, partnership_id)
      partnership = Scope.call(actor, :as_supplier).find_by(id: partnership_id)
      return OperationResult.failure(:not_found, path: [ :partnership_id ]) unless partnership

      Access.lock_pair!(supplier_tenant_id: partnership.owner_tenant_id, buyer_tenant_id: partnership.buyer_tenant_id)
      partnership.lock!
      return OperationResult.failure(:conflict, message: "Partnership is revoked") unless partnership.active?

      yield partnership
      OperationResult.success(Directory.partnership(actor, partnership.id))
    end

    def self.permission!(permission)
      permission.to_s.tap do |value|
        raise ArgumentError, "unknown permission: #{value}" unless PartnershipGrant::PERMISSIONS.include?(value)
      end
    end
    private_class_method :with_active_partnership, :permission!
  end
end
