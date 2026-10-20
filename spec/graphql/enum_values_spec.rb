require "rails_helper"

# GraphQL の enum の値が、値を作るか受け付ける公開 API の一覧と同じ集合である（docs/guides/packs-and-packwerk.md「公開 API を出す」）。
# 一覧に値を足して enum に足し忘れると、その値を持つ問い合わせを実行したときに初めて落ちる。
# 順は比べない。enum の宣言の順を並べ方に使う読み手は無く、並べ方は各一覧の順か SORT_ORDER が持つ
RSpec.describe "GraphQL の enum と公開 API の一覧" do
  # enum の型ごとの、比べる公開 API の定数の名前。Hash はキーを比べる。比べる相手は、値を作るか受け付けるコードが読む一覧か、
  # 値を作る式との一致を各パッケージの spec が確かめる一覧に限る。どちらでもない写しの定数は、作る側に値を足しても変わらない
  compared = {
    "Types::PurchaseOrderStatusType" => "Purchasing::PurchaseOrders::STATUSES",
    "Types::SalesOrderStatusType" => "Sales::SalesOrders::STATUSES",
    "Types::ShipmentRequestStatusType" => "Fulfillment::ShipmentRequests::STATUSES",
    "Types::PurchaseOrderTimelineKindType" => "Purchasing::PurchaseOrders::TIMELINE_KINDS",
    "Types::StockAdjustmentType" => "Inventory::Adjustment::TYPES",
    "Types::StockMovementKindType" => "Inventory::Stocks::MOVEMENT_EFFECTS",
    "Types::StockOrderFieldType" => "Inventory::Stocks::ORDER_COLUMNS",
    "Types::ImportKindType" => "Imports::CsvFormat::COLUMNS",
    "Types::PartnershipPermissionType" => "Partnerships::Access::PERMISSIONS",
    "Types::UserErrorCodeType" => "OperationResult::CODES",
    "Types::OrderDirectionType" => "Page::Sort::DIRECTIONS"
  }

  # 比べない enum の型と理由。どれも、一覧を定数に出しても作る側が読まないので、足し忘れを捕まえない
  order_fields = "並べてよい列の表は、公開 API が操作者から作る private のメソッドで、定数の一覧が無い。" \
    "enum にだけある列は、その列で並べたときに Page::Sort.of が拒む"
  uncompared = {
    "Types::ItemOrderFieldType" => order_fields,
    "Types::PurchaseOrderOrderFieldType" => order_fields,
    "Types::SalesOrderOrderFieldType" => order_fields,
    "Types::ShipmentRequestOrderFieldType" => order_fields,
    "Types::CancellationOutcomeType" => "値の一覧は DB の CHECK 制約にだけある",
    "Types::PartnershipStatusType" => "値の一覧は DB の CHECK 制約にだけある",
    "Types::ImportStatusType" => "値は導出の分岐（Imports::Import#status）にだけある",
    "Types::InvoiceStateType" => "値は導出の分岐（Billing::Invoices の state）にだけある"
  }

  # スキーマに登録された enum の型。読み込みの順に依らない。フィールドと引数から届く型だけが載り、extra_types で足した型は載らない。
  # スキーマは extra_types を使わない（app/graphql/factory_ops_schema.rb）ので、型は漏れない
  let(:enum_types) { FactoryOpsSchema.types.values.select { _1.kind.enum? && !_1.introspection? } }

  it "スキーマの enum の型は、どれも Types::BaseEnum の子で、比べる組か比べない表のどちらかにある" do
    listed = compared.select { |_, constant| Object.const_defined?(constant) }.keys + uncompared.keys

    expect(enum_types.reject { _1 < Types::BaseEnum }.map(&:graphql_name)).to eq([])
    expect(enum_types.map(&:name) - listed).to eq([])
    expect(compared.keys & uncompared.keys).to eq([])
    expect(compared.keys + uncompared.keys - enum_types.map(&:name)).to eq([])
  end

  compared.each do |type_name, constant_name|
    it "#{type_name} の値は #{constant_name} と同じ集合" do
      type = enum_types.find { _1.name == type_name }
      list = Object.const_get(constant_name)
      list = list.keys if list.is_a?(Hash)

      expect(type.values.values.map { _1.value.to_s }.to_set).to eq(list.to_set(&:to_s))
    end
  end
end
