# 単価の履歴を持つ前の DB の品目の単価と受注明細の有効日を、単価の履歴の形へ写す（docs/adr/006 決定 1）。
# items.unit_price を消すマイグレーションの前に、デプロイの担当者が 1 回流す。データの移行はマイグレーションに入れない（docs/adr/001 決定 4）。
# テナントを明示して 1 つずつ回る（decisions.md 2 章）。もう一度流しても行は増えない
namespace :sales do
  desc "items.unit_price を item_prices に写し、照合済みの受注明細の priced_on を受注日で埋める"
  task backfill_item_prices: :environment do
    tenant_ids = ActiveRecord::Base.lease_connection.select_values("SELECT id FROM tenants ORDER BY id")
    totals = tenant_ids.each_with_object(Hash.new(0)) do |tenant_id, sum|
      counts = Tenancy.with_tenant(tenant_id) { Sales::ItemPrices.backfill }
      puts "sales:backfill_item_prices: テナント #{tenant_id} の品目 #{counts[:items]} 件と明細 #{counts[:lines]} 件を写した" if counts.values.any?(&:positive?)
      counts.each { |key, count| sum[key] += count }
    end
    puts "sales:backfill_item_prices: 合わせて品目 #{totals[:items]} 件と明細 #{totals[:lines]} 件"
  end
end
