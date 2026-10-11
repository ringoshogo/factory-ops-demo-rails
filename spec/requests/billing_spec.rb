require "rails_helper"
require_relative "../support/events"

# 受注側の請求条件・締め・下書きの破棄・確定と、請求書と受領請求書の読み取りの配線（docs/architecture/graphql-schema.md
# 「mutation の一覧」「読み取りの一覧」）。業務の分岐は packs/billing/spec と packs/purchasing/spec の単体が確かめ、
# ここは公開 API の成功と失敗が GraphQL に写ることと、確定の写しが発注側に届くことを見る
RSpec.describe "請求の締め", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant, name: "青嵐精機工業") }
  let!(:customer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:customer_member) { Tenancy.with_tenant(customer.id) { FactoryBot.create(:user) } }
  # 請求対象明細の元の発注明細。受領請求書の明細は、自社の発注明細を引く
  let!(:purchase_order_lines) { Tenancy.with_tenant(customer.id) { FactoryBot.create_list(:purchase_order_line, 2) } }

  def mutate(name, selection, **input)
    query(<<~GRAPHQL, input:).fetch(name)
      mutation($input: #{name[0].upcase}#{name[1..]}Input!) { #{name}(input: $input) { #{selection} errors { code path } } }
    GRAPHQL
  end

  def invoice_selection = "id invoiceNumber state customer { name } periodStart periodEnd issuedAt subtotal taxTotal total " \
    "taxSummaries { taxRatePercent taxableAmount taxAmount } items { nodes { itemName unitPrice quantity amount taxRatePercent inspectedOn } }"

  def unbilled_count = query("{ supplier { billableItems { nodes { id } } } }").dig("supplier", "billableItems", "nodes").size

  # 取引関係を結んだ取引先に、9 月に検収された未請求明細を 2 つ持たせる
  before do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: customer.id)
      FactoryBot.create(:billable_item, customer_tenant_id: customer.id, inspected_on: Date.new(2026, 9, 5), unit_price: 105, quantity: 3,
        source_purchase_order_line_id: purchase_order_lines[0].id)
      FactoryBot.create(:billable_item, customer_tenant_id: customer.id, inspected_on: Date.new(2026, 9, 18), unit_price: 99,
        quantity: 2, tax_rate_percent: 8, item_name: "ナット M8", source_purchase_order_line_id: purchase_order_lines[1].id)
    end
    login_as(supplier_admin)
  end

  def close_september
    mutate("setBillingTerm", "billingTerm { closingDay }", customerTenantId: customer.id, closingDay: 20)
    mutate("closeBillingPeriod", "invoice { id }", customerTenantId: customer.id, closingDate: "2026-09-20").dig("invoice", "id")
  end

  it "請求条件を決めて締め、下書きの請求書を番号の空のまま読み、破棄すると明細が未請求に戻る" do
    term = mutate("setBillingTerm", "billingTerm { customer { name } closingDay }", customerTenantId: customer.id, closingDay: 20)
    expect(term).to eq("errors" => [], "billingTerm" => { "customer" => { "name" => "組立メーカー" }, "closingDay" => 20 })
    expect(query("{ supplier { billingTerms { closingDay } } }")).to eq("supplier" => { "billingTerms" => [ { "closingDay" => 20 } ] })
    expect(unbilled_count).to eq(2)

    closed = mutate("closeBillingPeriod", "invoice { #{invoice_selection} }", customerTenantId: customer.id, closingDate: "2026-09-20")
    invoice = closed.fetch("invoice")
    expect(closed.fetch("errors")).to eq([])
    expect(invoice).to include("invoiceNumber" => nil, "state" => "DRAFT", "customer" => { "name" => "組立メーカー" },
      "periodStart" => "2026-09-05", "periodEnd" => "2026-09-20", "issuedAt" => nil,
      "subtotal" => "513", "taxTotal" => "46", "total" => "559",
      "taxSummaries" => [ { "taxRatePercent" => 8, "taxableAmount" => "198", "taxAmount" => "15" },
                          { "taxRatePercent" => 10, "taxableAmount" => "315", "taxAmount" => "31" } ])
    expect(invoice.dig("items", "nodes")).to contain_exactly(
      { "itemName" => "六角ボルト M8", "unitPrice" => "105", "quantity" => 3, "amount" => "315", "taxRatePercent" => 10, "inspectedOn" => "2026-09-05" },
      { "itemName" => "ナット M8", "unitPrice" => "99", "quantity" => 2, "amount" => "198", "taxRatePercent" => 8, "inspectedOn" => "2026-09-18" }
    )
    expect(unbilled_count).to eq(0)

    # 下書きでも、invoiceNumber を選んだ一覧と 1 件の読み取りがエラーにならず空を返す
    expect(query("{ supplier { invoices { nodes { id invoiceNumber state } } } }"))
      .to eq("supplier" => { "invoices" => { "nodes" => [ { "id" => invoice.fetch("id"), "invoiceNumber" => nil, "state" => "DRAFT" } ] } })
    expect(query("query($id: ID!) { supplier { invoice(id: $id) { invoiceNumber state } } }", id: invoice.fetch("id")))
      .to eq("supplier" => { "invoice" => { "invoiceNumber" => nil, "state" => "DRAFT" } })

    expect(mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: invoice.fetch("id")))
      .to eq("errors" => [], "discardedInvoiceId" => invoice.fetch("id"))
    expect(query("{ supplier { invoices { nodes { id } } } }").dig("supplier", "invoices", "nodes")).to eq([])
    expect(unbilled_count).to eq(2)
  end

  it "締めと請求条件と破棄の失敗は、ユーザーエラーに写って何も書かない" do
    expect(mutate("setBillingTerm", "billingTerm { closingDay }", customerTenantId: customer.id, closingDay: 30))
      .to eq("billingTerm" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "closingDay" ] } ])
    expect(mutate("closeBillingPeriod", "invoice { id }", customerTenantId: customer.id, closingDate: "2026-09-20"))
      .to eq("invoice" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => [ "customerTenantId" ] } ])

    mutate("setBillingTerm", "billingTerm { closingDay }", customerTenantId: customer.id, closingDay: 20)
    expect(mutate("closeBillingPeriod", "invoice { id }", customerTenantId: customer.id, closingDate: "2026-09-21"))
      .to eq("invoice" => nil, "errors" => [ { "code" => "INVALID_INPUT", "path" => [ "closingDate" ] } ])
    expect(mutate("closeBillingPeriod", "invoice { id }", customerTenantId: customer.id, closingDate: "2026-08-20"))
      .to eq("invoice" => nil, "errors" => [ { "code" => "CONFLICT", "path" => nil } ])
    expect(query("{ supplier { invoices { nodes { id } } } }").dig("supplier", "invoices", "nodes")).to eq([])

    issued = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:invoice, :issued, customer_tenant_id: customer.id) }
    expect(mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: issued.id))
      .to eq("discardedInvoiceId" => nil, "errors" => [ { "code" => "CONFLICT", "path" => nil } ])
    expect(mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: SecureRandom.uuid))
      .to eq("discardedInvoiceId" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => nil } ])
  end

  it "請求条件の設定・締め・破棄は相手テナントに効果が及ばないので、監査の行を書かない" do
    mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: close_september)

    expect(Tenancy.with_tenant(supplier.id) { AuditLog.count }).to eq(0)
  end

  it "確定すると請求番号が振られて監査の行が残り、イベントを流すと発注側が受領請求書を読める" do
    invoice_id = close_september

    issued = mutate("issueInvoice", "invoice { id invoiceNumber state issuedAt total }", invoiceId: invoice_id)
    expect(issued).to match("errors" => [], "invoice" => { "id" => invoice_id, "invoiceNumber" => "INV-000001", "state" => "ISSUED",
      "issuedAt" => be_present, "total" => "559" })
    expect(Tenancy.with_tenant(supplier.id) do
      AuditLog.where(action: "invoice.issue").pluck(:actor_user_id, :target_type, :target_id, :counterparty_tenant_id)
    end).to eq([ [ supplier_admin.id, "Invoice", invoice_id, customer.id ] ])

    deliver_enqueued_events
    login_as(customer_member)
    received = query(<<~GRAPHQL).dig("buyer", "receivedInvoices", "nodes")
      { buyer { receivedInvoices { nodes {
        id invoiceNumber supplier { name } periodStart periodEnd issuedOn subtotal taxTotal total
        lines { purchaseOrderLine { id } itemName unitPrice quantity taxRatePercent amount }
      } } } }
    GRAPHQL
    expect(received).to match([ {
      "id" => be_present, "invoiceNumber" => "INV-000001", "supplier" => { "name" => "青嵐精機工業" }, "periodStart" => "2026-09-05",
      "periodEnd" => "2026-09-20", "issuedOn" => Date.current.iso8601, "subtotal" => "513", "taxTotal" => "46", "total" => "559",
      "lines" => contain_exactly(
        { "purchaseOrderLine" => { "id" => purchase_order_lines[0].id }, "itemName" => "六角ボルト M8", "unitPrice" => "105",
          "quantity" => 3, "taxRatePercent" => 10, "amount" => "315" },
        { "purchaseOrderLine" => { "id" => purchase_order_lines[1].id }, "itemName" => "ナット M8", "unitPrice" => "99",
          "quantity" => 2, "taxRatePercent" => 8, "amount" => "198" }
      )
    } ])
    expect(query("query($id: ID!) { buyer { receivedInvoice(id: $id) { invoiceNumber } } }", id: received.sole.fetch("id")))
      .to eq("buyer" => { "receivedInvoice" => { "invoiceNumber" => "INV-000001" } })
  end

  it "確定の失敗は、ユーザーエラーに写って番号を振らず、監査の行を書かない" do
    invoice_id = close_september
    mutate("issueInvoice", "invoice { id }", invoiceId: invoice_id)

    expect(mutate("issueInvoice", "invoice { id }", invoiceId: invoice_id))
      .to eq("invoice" => nil, "errors" => [ { "code" => "CONFLICT", "path" => nil } ])
    expect(mutate("issueInvoice", "invoice { id }", invoiceId: SecureRandom.uuid))
      .to eq("invoice" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => nil } ])
    expect(query("{ supplier { invoices { nodes { invoiceNumber } } } }").dig("supplier", "invoices", "nodes"))
      .to eq([ { "invoiceNumber" => "INV-000001" } ])
    expect(Tenancy.with_tenant(supplier.id) { AuditLog.count }).to eq(1)
  end

  it "member の確定は FORBIDDEN になり、下書きのまま残る" do
    invoice_id = close_september
    login_as(Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) })

    body = graphql_body("mutation($input: IssueInvoiceInput!) { issueInvoice(input: $input) { invoice { id } } }",
      input: { invoiceId: invoice_id })
    expect(body["errors"].map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
    login_as(supplier_admin)
    expect(query("query($id: ID!) { supplier { invoice(id: $id) { state } } }", id: invoice_id))
      .to eq("supplier" => { "invoice" => { "state" => "DRAFT" } })
  end
end
