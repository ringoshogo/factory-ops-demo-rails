# 一覧のために別のコンテキストへ写した値を、元から作り直す（docs/adr/011）。写しは 2 つで、在庫の品目の写しは受注の品目のコードと名前から、
# 出荷依頼の受注番号の写しは受注の受注番号から書き直す。作り直しはテナントごとにこのタスクが回す。受注番号の組はこのタスクが受注から受け取って出荷に渡し、
# 出荷の公開 API は受け取った組を書くだけの、このタスクにだけ呼ばれる操作者のいない入口である（docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。
# 写しを足した後の既存の DB を埋めるのと、写しを保つ経路の抜けを一致の spec が確かめるのに使う。
# テナントを明示して 1 つずつ回る（decisions.md 2 章）。写しが元と一致していれば何も書かず、もう一度流しても行は増えない
namespace :read_models do
  desc "在庫の品目の写しを受注の品目のコードと名前から、出荷依頼の受注番号の写しを受注の受注番号から作り直す"
  task rebuild: :environment do
    tenant_ids = ActiveRecord::Base.lease_connection.select_values("SELECT id FROM tenants ORDER BY id")
    labels = Inventory::ItemLabels::Counts.new(inserted: 0, updated: 0)
    order_numbers = 0
    tenant_ids.each do |tenant_id|
      counts, written = Tenancy.with_tenant(tenant_id) do
        [ Sales::Catalog.rebuild_item_labels, Fulfillment::ShipmentRequests.put_order_numbers(Sales::SalesOrders.order_numbers) ]
      end
      puts "read_models:rebuild: テナント #{tenant_id} の品目の写しを #{counts.inserted} 件足し、#{counts.updated} 件書き直した"
      puts "read_models:rebuild: テナント #{tenant_id} の出荷依頼の受注番号を #{written} 件書き直した"
      labels += counts
      order_numbers += written
    end
    puts "read_models:rebuild: 合わせて品目の写しを #{labels.inserted} 件足し、#{labels.updated} 件書き直した"
    puts "read_models:rebuild: 合わせて出荷依頼の受注番号を #{order_numbers} 件書き直した"
  end
end
