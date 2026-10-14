# 一覧のために別のコンテキストへ写した値を、元から作り直す（docs/adr/011）。いまは在庫の品目の写しだけで、受注の品目から書き直す。
# 写しを足した後の既存の DB を埋めるのと、写しを保つ経路の抜けを一致の spec が確かめるのに使う。
# テナントを明示して 1 つずつ回る（decisions.md 2 章）。写しが元と一致していれば何も書かず、もう一度流しても行は増えない
namespace :read_models do
  desc "在庫の品目の写しを、受注の品目のコードと名前から作り直す"
  task rebuild: :environment do
    tenant_ids = ActiveRecord::Base.lease_connection.select_values("SELECT id FROM tenants ORDER BY id")
    total = tenant_ids.sum(Inventory::ItemLabels::Counts.new(inserted: 0, updated: 0)) do |tenant_id|
      counts = Tenancy.with_tenant(tenant_id) { Sales::Catalog.rebuild_item_labels }
      puts "read_models:rebuild: テナント #{tenant_id} の品目の写しを #{counts.inserted} 件足し、#{counts.updated} 件書き直した"
      counts
    end
    puts "read_models:rebuild: 合わせて品目の写しを #{total.inserted} 件足し、#{total.updated} 件書き直した"
  end
end
