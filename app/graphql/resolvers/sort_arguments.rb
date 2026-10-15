module Resolvers
  # 一覧の並べ替えの引数（docs/architecture/graphql-schema.md「ページングと N+1」）。orderBy が 1 つ目の列、thenBy が 2 つ目からの列で、
  # 公開 API には列の順の配列で渡す。orderBy をリストに変えると比較器が破壊的な変更に分類するので、省いてよい thenBy を足した
  module SortArguments
    extend ActiveSupport::Concern

    # orderBy を省いた空でない thenBy、列の数の上限（Page::MAX_SORTS）を超える並べ替え、同じ列の重なりを、引数の検証でトップレベルのエラーにする
    class Validator < GraphQL::Schema::Validator
      def validate(_object, _context, value)
        order_by, then_by = value.values_at(:order_by, :then_by)
        return if then_by.blank?
        return "thenBy requires orderBy" if order_by.nil?

        fields = [ order_by, *then_by ].map { _1[:field] }
        return "orderBy and thenBy accept at most #{Page::MAX_SORTS} fields" if fields.size > Page::MAX_SORTS

        "orderBy and thenBy repeat a field" unless fields.uniq.size == fields.size
      end
    end

    class_methods do
      def sort_arguments(order_type)
        argument :order_by, order_type, required: false
        argument :then_by, [ order_type ], required: false
        validates Validator => {}
      end
    end

    def sort_list(order_by, then_by) = [ order_by, *then_by ].compact.map(&:to_h)
  end
end
