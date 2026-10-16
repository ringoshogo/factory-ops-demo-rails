module Mutations
  # 取消の審査を承認する。引当を解除して受注を取り消し、「取消承認」を出す。出荷は受注の取消を読んで出荷依頼を取消済にする。
  # 決着済みの審査と、引当が消費済み（出荷の計上が先に成立した）の受注は CONFLICT
  class ApproveCancellationReview < BaseMutation
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy, :review?
    audit "cancellation_review.approve", target: ->(target:, **) { target }, counterparty: ->(result:, **) { result.customer_tenant_id }

    argument :cancellation_review_id, ID
    result_field :sales_order, Types::SalesOrderType

    # 自社の審査だけを引く。見えない ID は NOT_FOUND になる
    def find_target(cancellation_review_id:, **)
      Sales::CancellationReviews.find(current_user, cancellation_review_id)
    end

    def perform(target, **)
      Sales::CancellationReviews.approve(current_user, cancellation_review_id: target.id)
    end
  end
end
