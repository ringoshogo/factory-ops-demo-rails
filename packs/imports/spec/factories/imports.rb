FactoryBot.define do
  # どれも Tenancy.with_tenant の中で作る
  factory :import_file, class: "Imports::ImportFile" do
    owner_tenant_id { Current.tenant_id }
    filename { "stocks.csv" }
    content { "item_code,quantity\n" }
    byte_size { content&.bytesize || 0 }
    uploaded_by_user_id { SecureRandom.uuid }
  end

  # 既定は、置いたファイルの在庫の取り込みで、まだジョブが動いていないもの
  factory :import, class: "Imports::Import" do
    owner_tenant_id { Current.tenant_id }
    import_file { association :import_file, owner_tenant_id: }
    kind { "stocks" }
    requested_by_user_id { SecureRandom.uuid }
  end

  factory :import_row, class: "Imports::ImportRow" do
    owner_tenant_id { Current.tenant_id }
    import { association :import, owner_tenant_id: }
    sequence(:row_number) { |n| n + 1 }
    data { [ "ITEM-1", "3" ] }
  end
end
