module Sales
  # 受注の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。受注は受注側だけが所有し、相手から読む経路は無い
  class SalesOrderPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    def list? = true

    # 受注・受注明細・取消の審査の値のどれにも使う
    def show? = record.owner_tenant_id == user.tenant_id

    # 引当は、自社のユーザーなら役割を問わない
    def allocate? = show?

    # 受注側の取消と、取消の審査の承認・却下は、取引を取り消す操作なので admin に限る
    # （docs/architecture/context-map.md「自社の中の役割」）
    def cancel? = user.admin? && show?
    def review? = user.admin? && show?
  end
end
