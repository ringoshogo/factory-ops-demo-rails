module Partnerships
  # 「発注側の操作者は、受注側テナントに対して permission の操作をしてよいか」に答える
  # （docs/architecture/data-model.md「取引関係と権限付与」）。有効な取引関係と権限付与の両方が要る。
  # 存在しないテナントも、関係の無いテナント・失効したテナントと同じく偽になる
  module Access
    PERMISSIONS = PartnershipGrant::PERMISSIONS

    # 発注側の操作者に permission を与えている受注側テナントの ID。他の relation の条件に埋め込む副問い合わせとして返す
    def self.permitting_suppliers(actor, permission:)
      raise ArgumentError, "unknown permission: #{permission}" unless PERMISSIONS.include?(permission.to_s)

      Scope.call(actor, :as_buyer).joins(:grants).where(partnership_grants: { permission: permission.to_s }).select(:owner_tenant_id)
    end

    # 答えを使って書き込む操作は lock: true を渡す。問い合わせの前に組のロックを取り、
    # 失効と権限の撤回がトランザクションの終わりまで割り込まないようにする（context-map.md「取引関係の失効」）
    def self.permitted?(actor, supplier_tenant_id:, permission:, lock: false)
      raise ArgumentError, "unknown permission: #{permission}" unless PERMISSIONS.include?(permission.to_s)

      lock_pair!(supplier_tenant_id:, buyer_tenant_id: actor.tenant_id) if lock
      Scope.call(actor, :as_buyer).where(owner_tenant_id: supplier_tenant_id)
        .joins(:grants).where(partnership_grants: { permission: permission.to_s }).exists?
    end

    # 受注側と発注側の組ごとのアドバイザリロックを、トランザクションの終わりまで取る。
    # 権限を確かめてから書く操作と、取引関係・権限付与を変える操作の両方が、確かめる・変える前に呼ぶ。
    # 取引関係の行のロックでは足りない。問い合わせはロックを取らずに読むので、失効と並べて待たせられないからである
    def self.lock_pair!(supplier_tenant_id:, buyer_tenant_id:)
      connection = Partnership.lease_connection
      raise ArgumentError, "lock_pair! はトランザクションの中で呼ぶ" unless connection.transaction_open?

      connection.exec_query("SELECT 1 FROM pg_advisory_xact_lock(hashtextextended($1, 0))", "Partnerships::Access",
        [ "partnership:#{supplier_tenant_id}:#{buyer_tenant_id}" ])
      nil
    end
  end
end
