module Sales
  # 品目の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。
  # scope は所有の条件を明示し、RLS に任せない。RLS は経路 1 の相手の公開品目も返すからである
  class ItemPolicy < ApplicationPolicy
    # 自社の品目。公開していないものも含む
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    # 経路 1：有効な取引関係と view_catalog の付与がある受注側の、公開品目だけ
    relation_scope(:published_catalog) do |relation, supplier_tenant_id:|
      next relation.none unless view_catalog?(supplier_tenant_id)

      relation.where(owner_tenant_id: supplier_tenant_id, published: true)
    end

    # 一覧と品目の登録は、自社のユーザーなら役割を問わない
    def list? = true

    def save? = true

    def show? = record.owner_tenant_id == user.tenant_id

    def manage? = show?

    def show_to_buyer? = record.is_a?(PublishedCatalog::Item) && view_catalog?(record.supplier_tenant_id)

    private

    # 一覧の品目ごとに show_to_buyer? を評価しても、問い合わせは受注側ごとに 1 回で済ませる
    def view_catalog?(supplier_tenant_id)
      remember([ :view_catalog, supplier_tenant_id ]) do
        Partnerships::Access.permitted?(user, supplier_tenant_id:, permission: :view_catalog)
      end
    end
  end
end
