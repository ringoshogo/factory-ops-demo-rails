module Imports
  # ファイル・取り込み・置き場の行の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。
  # 取り込みは書き込んだテナントだけが所有し、相手から読む経路は無い。scope は所有の条件を明示し、RLS に任せない
  class ImportPolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    def list? = true

    # 取り込みの値と、取り込みの依頼の値のどちらにも使う
    def show? = record.owner_tenant_id == user.tenant_id

    # 取り込みの開始。record は取り込みの依頼（ファイルと種類）で、規則は依頼の種類を見る。品目の CSV は単価の列を含み、
    # 単価は金額を決めるので admin に限る。在庫の CSV は役割を問わない（docs/architecture/context-map.md「自社の中の役割」）
    def start? = show? && (record.kind == "stocks" || user.admin?)
  end
end
