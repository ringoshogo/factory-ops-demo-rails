module Resolvers
  module Supplier
    # 受注・在庫・出荷・請求の集計を 1 つの型に束ねる（docs/architecture/graphql-schema.md「読み取りの一覧」）。
    # 集計はどれも自社の scope を掛けた公開 API が行い、どれも自社のユーザーなら役割を問わず読める。
    # 規則は受注の一覧と同じものを使う。ダッシュボードは受注の画面で、4 つの公開 API の一覧の規則はどれも同じ答えを返す
    class DashboardResolver < BaseResolver
      perspective :supplier
      authorize_with Sales::SalesOrderPolicy, :list?

      type Types::SupplierDashboardType, null: false

      # 業務の日付は日本時間で決める。アプリの時刻帯は UTC のままなので、Date.current では日本時間の 0〜9 時が前日になる
      def resolve = Types::SupplierDashboardType::Dashboard.new(business_date: Time.current.in_time_zone("Asia/Tokyo").to_date)
    end
  end
end
