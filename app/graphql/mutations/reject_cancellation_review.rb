module Mutations
  # 取消の審査を却下し、「取消却下」を出す。出荷は決着した審査を出荷停止と読まなくなる。決着済みの審査は CONFLICT
  class RejectCancellationReview < BaseMutation
    perspective :supplier
    authorize_with Sales::SalesOrderPolicy, :review?
    audit "cancellation_review.reject", target: ->(target:, **) { target }, counterparty: ->(result:, **) { result.customer_tenant_id }

    argument :cancellation_review_id, ID
    result_field :sales_order, Types::SalesOrderType

    # 自社の審査だけを引く。見えない ID は NOT_FOUND になる
    def find_target(cancellation_review_id:, **)
      Sales::CancellationReviews.find(current_user, cancellation_review_id)
    end

    def perform(target, **)
      Sales::CancellationReviews.reject(current_user, cancellation_review_id: target.id)
    end
  end
end
