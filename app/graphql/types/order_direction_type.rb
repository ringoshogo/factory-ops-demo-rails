module Types
  # 一覧の並べ替えの向き。どちらの向きでも、並べ替えの列の値の無い行を最後に置く
  class OrderDirectionType < BaseEnum
    graphql_name "OrderDirection"

    value "ASC", "昇順", value: :asc
    value "DESC", "降順", value: :desc
  end
end
