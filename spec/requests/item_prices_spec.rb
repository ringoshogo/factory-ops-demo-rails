require "rails_helper"
require_relative "../support/events"

# 販売単価の改定の予約・訂正と、単価の履歴・請求書の単価の説明の配線（docs/adr/006、docs/architecture/graphql-schema.md
# 「mutation の一覧」「役割による制限」）。業務の分岐は packs/sales/spec の単体が確かめ、ここは入口の役割と監査の行、
# 受注明細への単価の写しと請求書の説明が、GraphQL を通して効くことを見る
RSpec.describe "販売単価の履歴", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:buyer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:buyer_member) { Tenancy.with_tenant(buyer.id) { FactoryBot.create(:user) } }
  # 10/1 に 100 円で作った品目
  let!(:item) do
    travel_to(Time.zone.local(2026, 10, 1, 9)) do
      Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "BOLT-8", name: "六角ボルト M8", unit_price: 100) }
    end
  end

  def mutate(name, selection, **input)
    query(<<~GRAPHQL, input:).fetch(name)
      mutation($input: #{name[0].upcase}#{name[1..]}Input!) { #{name}(input: $input) { #{selection} errors { code path } } }
    GRAPHQL
  end

  # 品目 BOLT-8 の単価の行
  def prices(as_of: nil)
    query(<<~GRAPHQL, asOf: as_of&.iso8601).dig("supplier", "items", "nodes").find { _1["code"] == "BOLT-8" }.fetch("prices")
      query($asOf: ISO8601DateTime) { supplier { items { nodes { code prices(asOf: $asOf) { unitPrice validFrom validTo reason } } } } }
    GRAPHQL
  end

  def audit_rows(action)
    Tenancy.with_tenant(supplier.id) do
      AuditLog.where(action:).map { _1.attributes.slice("actor_user_id", "target_type", "target_id", "counterparty_tenant_id") }
    end
  end

  describe "saveItem" do
    # 既存の品目の単価は、admin でも member でも変えられない。改定と訂正は admin に限る 2 つの mutation だけが行う
    { "admin" => :supplier_admin, "member" => :supplier_member }.each do |role, user|
      it "#{role} は新しい品目を最初の単価で作れ、既存の品目の単価は変えられず、同じ単価なら名前を直せる" do
        login_as(public_send(user))

        created = mutate("saveItem", "item { code unitPrice prices { unitPrice validFrom validTo } }",
          code: "NUT-8", name: "ナット M8", unit: "個", unitPrice: "30")
        expect(created).to eq("errors" => [],
          "item" => { "code" => "NUT-8", "unitPrice" => "30", "prices" => [ { "unitPrice" => "30", "validFrom" => nil, "validTo" => nil } ] })

        changed = mutate("saveItem", "item { id }", code: "BOLT-8", name: "六角ボルト M8", unit: "個", unitPrice: "150")
        expect(changed).to eq("item" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "unitPrice" ] } ])
        expect(prices).to eq([ { "unitPrice" => "100", "validFrom" => nil, "validTo" => nil, "reason" => nil } ])

        renamed = mutate("saveItem", "item { name unitPrice }", code: "BOLT-8", name: "六角ボルト M8 改", unit: "個", unitPrice: "100")
        expect(renamed).to eq("errors" => [], "item" => { "name" => "六角ボルト M8 改", "unitPrice" => "100" })
      end
    end

    it "既存の品目の単価を変えようとしたときの説明は、改定と訂正の mutation を案内する" do
      login_as(supplier_admin)
      body = graphql_body(<<~GRAPHQL, input: { code: "BOLT-8", name: "六角ボルト M8", unit: "個", unitPrice: "150" })
        mutation($input: SaveItemInput!) { saveItem(input: $input) { errors { message } } }
      GRAPHQL

      expect(body.dig("data", "saveItem", "errors").sole.fetch("message")).to include("scheduleItemPrice", "correctItemPrice")
    end
  end

  describe "scheduleItemPrice・correctItemPrice" do
    let(:today) { Time.zone.local(2026, 10, 12, 10) }

    before { travel_to(today) }
    after { travel_back }

    it "admin が改定を予約し、訂正すると、単価の行が足され、品目を対象にした監査の行が相手を空にして残る" do
      login_as(supplier_admin)

      scheduled = mutate("scheduleItemPrice", "item { unitPrice prices { unitPrice validFrom validTo } }",
        itemId: item.id, unitPrice: "120", effectiveOn: "2026-11-01")
      expect(scheduled).to eq("errors" => [], "item" => { "unitPrice" => "100", "prices" => [
        { "unitPrice" => "100", "validFrom" => nil, "validTo" => "2026-11-01" },
        { "unitPrice" => "120", "validFrom" => "2026-11-01", "validTo" => nil }
      ] })
      expect(audit_rows("item_price.schedule"))
        .to eq([ { "actor_user_id" => supplier_admin.id, "target_type" => "Item", "target_id" => item.id, "counterparty_tenant_id" => nil } ])

      row_id = query("{ supplier { items { nodes { prices { id validTo } } } } }")
        .dig("supplier", "items", "nodes").sole.fetch("prices").find { _1["validTo"] == "2026-11-01" }.fetch("id")
      travel 1.hour
      corrected = mutate("correctItemPrice", "item { unitPrice }", itemPriceId: row_id, unitPrice: "95", reason: "入力の誤り")
      expect(corrected).to eq("errors" => [], "item" => { "unitPrice" => "95" })
      expect(audit_rows("item_price.correct")).to eq([
        { "actor_user_id" => supplier_admin.id, "target_type" => "ItemPrice", "target_id" => row_id, "counterparty_tenant_id" => nil }
      ])
      expect(prices).to eq([
        { "unitPrice" => "95", "validFrom" => nil, "validTo" => "2026-11-01", "reason" => "入力の誤り" },
        { "unitPrice" => "120", "validFrom" => "2026-11-01", "validTo" => nil, "reason" => nil }
      ])
      # 予約の後・訂正の前の記録時点では、訂正の前の行を信じていた
      expect(prices(as_of: today + 30.minutes).map { _1["unitPrice"] }).to eq(%w[100 120])

      # 閉じた行の訂正は CONFLICT で、監査の行を書かない
      expect(mutate("correctItemPrice", "item { id }", itemPriceId: row_id, unitPrice: "90", reason: "再訂正"))
        .to eq("item" => nil, "errors" => [ { "code" => "CONFLICT", "path" => [ "itemPriceId" ] } ])
      expect(audit_rows("item_price.correct").size).to eq(1)
    end

    it "改定日が過去なら、項目を指す INVALID_INPUT で何も書かない" do
      login_as(supplier_admin)

      expect(mutate("scheduleItemPrice", "item { id }", itemId: item.id, unitPrice: "120", effectiveOn: "2026-10-11"))
        .to eq("item" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "effectiveOn" ] } ])
      expect(prices.size).to eq(1)
      expect(audit_rows("item_price.schedule")).to be_empty
    end

    # 単価の列は bigint。上限を超える値は、トップレベルのエラーにせず、項目を指すユーザーエラーにする
    it "単価は bigint の最大値ちょうどを受け付け、最大値 + 1 は項目を指す INVALID_INPUT で何も書かない" do
      login_as(supplier_admin)

      expect(mutate("scheduleItemPrice", "item { id }", itemId: item.id, unitPrice: "9223372036854775808", effectiveOn: "2026-11-01"))
        .to eq("item" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "unitPrice" ] } ])
      expect(prices.size).to eq(1)
      scheduled = mutate("scheduleItemPrice", "item { id }", itemId: item.id, unitPrice: "9223372036854775807", effectiveOn: "2026-11-01")
      expect(scheduled["errors"]).to eq([])
      expect(prices.map { _1["unitPrice"] }).to eq(%w[100 9223372036854775807])

      row_id = query("{ supplier { items { nodes { prices { id validFrom } } } } }")
        .dig("supplier", "items", "nodes").sole.fetch("prices").find { _1["validFrom"] == "2026-11-01" }.fetch("id")
      travel 1.hour
      expect(mutate("correctItemPrice", "item { id }", itemPriceId: row_id, unitPrice: "9223372036854775808", reason: "入力の誤り"))
        .to eq("item" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "unitPrice" ] } ])
      expect(mutate("correctItemPrice", "item { id }", itemPriceId: row_id, unitPrice: "9223372036854775806", reason: "入力の誤り")["errors"])
        .to eq([])
      expect(audit_rows("item_price.correct").size).to eq(1)
    end

    it "member には FORBIDDEN で、単価の行も監査の行も書かない" do
      login_as(supplier_member)
      row_id = query("{ supplier { items { nodes { prices { id } } } } }").dig("supplier", "items", "nodes").sole.dig("prices", 0, "id")

      [
        [ "ScheduleItemPrice", "scheduleItemPrice", { itemId: item.id, unitPrice: "120", effectiveOn: "2026-11-01" } ],
        [ "CorrectItemPrice", "correctItemPrice", { itemPriceId: row_id, unitPrice: "90", reason: "入力の誤り" } ]
      ].each do |type, name, input|
        body = graphql_body("mutation($input: #{type}Input!) { #{name}(input: $input) { item { id } } }", input:)
        expect(body.fetch("errors").map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      end
      expect(prices.size).to eq(1)
      expect(audit_rows("item_price.schedule") + audit_rows("item_price.correct")).to be_empty
    end
  end

  describe "カタログの単価" do
    before do
      Tenancy.with_tenant(supplier.id) do
        item.update!(published: true)
        FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[view_catalog])
      end
    end

    def catalog_prices
      login_as(buyer_member)
      buyer_prices = query("{ buyer { suppliers { catalog { nodes { unitPrice } } } } }").dig("buyer", "suppliers").sole
        .dig("catalog", "nodes").map { _1["unitPrice"] }
      login_as(supplier_admin)
      [ buyer_prices, query("{ supplier { items { nodes { unitPrice } } } }").dig("supplier", "items", "nodes").map { _1["unitPrice"] } ]
    end

    it "受注側の品目と発注側のカタログは、改定日の前日まで今日の単価を返し、改定日から改定後の単価を返す" do
      travel_to(Time.zone.local(2026, 10, 30, 10)) do
        login_as(supplier_admin)
        mutate("scheduleItemPrice", "item { id }", itemId: item.id, unitPrice: "120", effectiveOn: "2026-10-31")
        expect(catalog_prices).to eq([ %w[100], %w[100] ])
      end

      travel_to(Time.zone.local(2026, 10, 31, 10)) { expect(catalog_prices).to eq([ %w[120], %w[120] ]) }
    end
  end

  describe "受注明細への単価の写し" do
    before do
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders])
        FactoryBot.create(:customer_part_mapping, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item:)
      end
    end

    def place_on(time)
      travel_to(time) do
        login_as(buyer_member)
        mutate("placePurchaseOrder", "purchaseOrder { id }", supplierTenantId: supplier.id, lines: [ { partNumber: "MY-BOLT", quantity: 1 } ])
        deliver_enqueued_events
      end
    end

    it "改定日の前日の発注は元の単価を、当日の発注は改定後の単価を、受注日を有効日にして写す" do
      travel_to(Time.zone.local(2026, 10, 30, 10)) do
        login_as(supplier_admin)
        mutate("scheduleItemPrice", "item { id }", itemId: item.id, unitPrice: "120", effectiveOn: "2026-10-31")
      end

      place_on(Time.zone.local(2026, 10, 30, 11))
      place_on(Time.zone.local(2026, 10, 31, 11))

      login_as(supplier_admin)
      orders = query("{ supplier { salesOrders { nodes { orderDate lines { unitPrice } } } } }").dig("supplier", "salesOrders", "nodes")
      expect(orders.map { [ _1["orderDate"], _1["lines"].sole["unitPrice"] ] })
        .to contain_exactly([ "2026-10-30", "100" ], [ "2026-10-31", "120" ])
      priced_on = Tenancy.with_tenant(supplier.id) do
        ActiveRecord::Base.lease_connection.select_values("SELECT priced_on FROM sales_order_lines ORDER BY priced_on")
      end
      expect(priced_on).to eq([ Date.new(2026, 10, 30), Date.new(2026, 10, 31) ])
    end
  end

  describe "BillableItem.priceExplanation" do
    # 10/15 の受注で 100 円を写した明細を、10/20 に検収して請求対象にする
    let!(:line) do
      Tenancy.with_tenant(supplier.id) do
        order = FactoryBot.create(:sales_order, customer_tenant_id: buyer.id, order_date: Date.new(2026, 10, 15))
        FactoryBot.create(:sales_order_line, :matched, sales_order: order, item_id: item.id, unit_price: 100)
      end
    end

    before do
      Tenancy.with_tenant(supplier.id) do
        FactoryBot.create(:partnership, buyer_tenant_id: buyer.id)
        FactoryBot.create(:billing_term, customer_tenant_id: buyer.id, closing_day: 31)
        FactoryBot.create(:billable_item, customer_tenant_id: buyer.id, sales_order_line_id: line.id, unit_price: 100,
          inspected_on: Date.new(2026, 10, 20))
      end
    end

    def explanations(invoice_id)
      query(<<~GRAPHQL, id: invoice_id).dig("supplier", "invoice", "items", "nodes").map { _1.fetch("priceExplanation") }
        query($id: ID!) {
          supplier { invoice(id: $id) { items { nodes { priceExplanation { orderedUnitPrice pricedOn unitPriceAsOfIssue unitPriceNow } } } } }
        }
      GRAPHQL
    end

    it "発行の後に単価を訂正すると、発行の時点の単価と、いまの単価を別々に返す。下書きでは発行の時点の単価は空" do
      invoice_id = travel_to(Time.zone.local(2026, 11, 1, 9)) do
        login_as(supplier_admin)
        mutate("closeBillingPeriod", "invoice { id }", customerTenantId: buyer.id, closingDate: "2026-10-31").dig("invoice", "id")
      end
      login_as(supplier_admin)
      expect(explanations(invoice_id))
        .to eq([ { "orderedUnitPrice" => "100", "pricedOn" => "2026-10-15", "unitPriceAsOfIssue" => nil, "unitPriceNow" => "100" } ])

      # セッションは時刻を進めると切れるので、時刻ごとにログインし直す
      travel_to(Time.zone.local(2026, 11, 1, 10)) do
        login_as(supplier_admin)
        mutate("issueInvoice", "invoice { id }", invoiceId: invoice_id)
      end
      travel_to(Time.zone.local(2026, 11, 2, 10)) do
        login_as(supplier_admin)
        row_id = query("{ supplier { items { nodes { prices { id } } } } }").dig("supplier", "items", "nodes").sole.dig("prices", 0, "id")
        mutate("correctItemPrice", "item { id }", itemPriceId: row_id, unitPrice: "90", reason: "10 月の単価の入力の誤り")
      end

      login_as(supplier_admin)
      expect(explanations(invoice_id))
        .to eq([ { "orderedUnitPrice" => "100", "pricedOn" => "2026-10-15", "unitPriceAsOfIssue" => "100", "unitPriceNow" => "90" } ])
    end
  end
end
