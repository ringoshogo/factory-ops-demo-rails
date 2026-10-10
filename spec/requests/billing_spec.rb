require "rails_helper"

# 受注側の請求条件・締め・下書きの破棄と、請求書の読み取りの配線（docs/architecture/graphql-schema.md「mutation の一覧」
# 「読み取りの一覧」）。業務の分岐は packs/billing/spec の単体が確かめ、ここは公開 API の成功と失敗が GraphQL に写ることを見る
RSpec.describe "請求の締め", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:customer) { FactoryBot.create(:tenant, name: "組立メーカー") }
  let(:supplier_member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }

  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def graphql(query, **variables)
    post "/graphql", params: { query:, variables: }, as: :json
    expect(response.parsed_body["errors"]).to be_nil
    response.parsed_body.fetch("data")
  end

  def mutate(name, selection, **input)
    graphql(<<~GRAPHQL, input:).fetch(name)
      mutation($input: #{name[0].upcase}#{name[1..]}Input!) { #{name}(input: $input) { #{selection} errors { code path } } }
    GRAPHQL
  end

  def invoice_selection = "id invoiceNumber state customer { name } periodStart periodEnd issuedAt subtotal taxTotal total " \
    "taxSummaries { taxRatePercent taxableAmount taxAmount } items { nodes { itemName unitPrice quantity amount taxRatePercent inspectedOn } }"

  def unbilled_count = graphql("{ supplier { billableItems { nodes { id } } } }").dig("supplier", "billableItems", "nodes").size

  # 取引関係を結んだ取引先に、9 月に検収された未請求明細を 2 つ持たせる
  before do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: customer.id)
      FactoryBot.create(:billable_item, customer_tenant_id: customer.id, inspected_on: Date.new(2026, 9, 5), unit_price: 105, quantity: 3)
      FactoryBot.create(:billable_item, customer_tenant_id: customer.id, inspected_on: Date.new(2026, 9, 18), unit_price: 99,
        quantity: 2, tax_rate_percent: 8, item_name: "ナット M8")
    end
    login_as(supplier_member)
  end

  it "請求条件を決めて締め、下書きの請求書を番号の空のまま読み、破棄すると明細が未請求に戻る" do
    term = mutate("setBillingTerm", "billingTerm { customer { name } closingDay }", customerTenantId: customer.id, closingDay: 20)
    expect(term).to eq("errors" => [], "billingTerm" => { "customer" => { "name" => "組立メーカー" }, "closingDay" => 20 })
    expect(graphql("{ supplier { billingTerms { closingDay } } }")).to eq("supplier" => { "billingTerms" => [ { "closingDay" => 20 } ] })
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
    expect(graphql("{ supplier { invoices { nodes { id invoiceNumber state } } } }"))
      .to eq("supplier" => { "invoices" => { "nodes" => [ { "id" => invoice.fetch("id"), "invoiceNumber" => nil, "state" => "DRAFT" } ] } })
    expect(graphql("query($id: ID!) { supplier { invoice(id: $id) { invoiceNumber state } } }", id: invoice.fetch("id")))
      .to eq("supplier" => { "invoice" => { "invoiceNumber" => nil, "state" => "DRAFT" } })

    expect(mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: invoice.fetch("id")))
      .to eq("errors" => [], "discardedInvoiceId" => invoice.fetch("id"))
    expect(graphql("{ supplier { invoices { nodes { id } } } }").dig("supplier", "invoices", "nodes")).to eq([])
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
    expect(graphql("{ supplier { invoices { nodes { id } } } }").dig("supplier", "invoices", "nodes")).to eq([])

    issued = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:invoice, :issued, customer_tenant_id: customer.id) }
    expect(mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: issued.id))
      .to eq("discardedInvoiceId" => nil, "errors" => [ { "code" => "CONFLICT", "path" => nil } ])
    expect(mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: SecureRandom.uuid))
      .to eq("discardedInvoiceId" => nil, "errors" => [ { "code" => "NOT_FOUND", "path" => nil } ])
  end

  it "どの mutation も相手テナントに効果が及ばないので、監査の行を書かない" do
    mutate("setBillingTerm", "billingTerm { closingDay }", customerTenantId: customer.id, closingDay: 20)
    invoice_id = mutate("closeBillingPeriod", "invoice { id }", customerTenantId: customer.id, closingDate: "2026-09-20").dig("invoice", "id")
    mutate("discardDraftInvoice", "discardedInvoiceId", invoiceId: invoice_id)

    expect(Tenancy.with_tenant(supplier.id) { AuditLog.count }).to eq(0)
  end
end
