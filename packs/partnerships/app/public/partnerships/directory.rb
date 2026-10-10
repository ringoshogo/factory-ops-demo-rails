module Partnerships
  # 取引関係の読み取り（docs/architecture/graphql-schema.md「読み取りの一覧」）
  module Directory
    # 受注側の一覧。失効した関係も含む
    def self.for_supplier(actor)
      to_values(Scope.call(actor, :as_supplier).order(id: :desc))
    end

    # 経路 2。自社が発注側の有効な関係だけ。失効すると空になる
    def self.for_buyer(actor)
      to_values(Scope.call(actor, :as_buyer).order(id: :desc))
    end

    # 経路 2 の関係を、受注側テナントで 1 件引く。関係の無い相手・失効した相手・存在しないテナントは、どれも nil になる
    def self.for_buyer_supplier(actor, supplier_tenant_id)
      to_values(Scope.call(actor, :as_buyer).where(owner_tenant_id: supplier_tenant_id)).first
    end

    # 自社が受注側の関係を 1 件引く。見えない ID は存在しない ID と同じく nil になる
    def self.partnership(actor, id)
      to_values(Scope.call(actor, :as_supplier).where(id:)).first
    end

    # 自社が受注側の取引関係（失効したものを含む）の相手か。存在しないテナントも偽になる
    def self.customer?(actor, tenant_id)
      Scope.call(actor, :as_supplier).exists?(buyer_tenant_id: tenant_id)
    end

    # 伝票が指す相手テナント（発注の受注側・受注の発注側）の ID ごとの名前。取引関係が失効しても引ける
    def self.tenants(actor, ids)
      raise ArgumentError, "actor is required" unless actor.is_a?(Actor)

      Tenant.where(id: ids).to_h { [ _1.id, TenantSummary.new(id: _1.id, name: _1.name) ] }
    end

    # 自社のユーザーの ID ごとの名前。監査ログの操作者を示すのに使う。
    # Tenancy.with_tenant の中で呼ぶ。RLS の下で引くので、別テナントのユーザーは含まない
    def self.user_names(actor, ids)
      raise ArgumentError, "actor is required" unless actor.is_a?(Actor)

      User.where(id: ids).pluck(:id, :name).to_h
    end

    def self.to_values(relation)
      partnerships = relation.to_a
      permissions = PartnershipGrant.where(partnership_id: partnerships.map(&:id))
        .pluck(:partnership_id, :permission)
        .group_by(&:first).transform_values { |rows| rows.map(&:last).sort_by { PartnershipGrant::PERMISSIONS.index(_1) } }
      tenant_ids = partnerships.flat_map { [ _1.owner_tenant_id, _1.buyer_tenant_id ] }.uniq
      tenants = Tenant.where(id: tenant_ids).to_h { [ _1.id, TenantSummary.new(id: _1.id, name: _1.name) ] }

      partnerships.map do |partnership|
        PartnershipValue.new(
          id: partnership.id,
          supplier: tenants.fetch(partnership.owner_tenant_id),
          buyer: tenants.fetch(partnership.buyer_tenant_id),
          status: partnership.status,
          revoked_at: partnership.revoked_at,
          permissions: permissions.fetch(partnership.id, [])
        )
      end
    end
    private_class_method :to_values
  end
end
