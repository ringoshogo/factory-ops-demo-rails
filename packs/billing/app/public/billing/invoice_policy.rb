module Billing
  # 請求条件・請求対象明細・請求書の可視範囲と規則（docs/architecture/graphql-schema.md「認可」）。
  # 請求は受注側だけが所有し、相手から読む経路は無い。scope は所有の条件を明示し、RLS に任せない
  class InvoicePolicy < ApplicationPolicy
    relation_scope(:own) { |relation| relation.where(owner_tenant_id: user.tenant_id) }

    def list? = true

    # 請求条件・請求対象明細・請求書・税率ごとの集計の値のどれにも使う
    def show? = record.owner_tenant_id == user.tenant_id

    # 請求条件の設定と締めは、自社のユーザーなら役割を問わない。どちらも対象を引かないので操作者に対して評価する。
    # 取引先が自社の取引関係の相手であることは、公開 API が確かめる
    def set_term? = true
    def close? = true

    # 下書きの破棄は、自社の請求書なら役割を問わない
    def discard? = show?
  end
end
