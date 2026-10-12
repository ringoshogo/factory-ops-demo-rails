require "rails_helper"

# 受注側の品目の保存。品目コードで引き、無ければ非公開で作り、あれば更新する。公開の状態は set_published だけが変える。
# 新しい品目は最初の単価を持ち、既存の品目の単価は変えない（docs/architecture/graphql-schema.md「mutation の一覧」）
RSpec.describe Sales::Catalog do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "")
  end

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

  def save(code: "N-1", name: "新品目", unit: "個", unit_price: 300, tax_rate_percent: 10)
    described_class.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent:)
  end

  def price_rows = Sales::ItemPrice.pluck(:unit_price, :valid_period)

  it "新しいコードなら非公開で作って最初の単価を有効期間 (,) の行にし、同じコードなら同じ品目を更新する" do
    created = save.value
    expect(created).to have_attributes(code: "N-1", name: "新品目", unit_price: 300, tax_rate_percent: 10, published: false)
    expect(price_rows).to eq([ [ 300, -Float::INFINITY...Float::INFINITY ] ])
    expect(Sales::ItemPrice.sole.recorded_by_user_id).to eq(actor.user_id)

    updated = save(name: "改名", tax_rate_percent: 8).value

    expect(updated).to have_attributes(id: created.id, name: "改名", unit_price: 300, tax_rate_percent: 8)
    expect(described_class.items(actor, first: 10, after: nil).values.map(&:id)).to eq([ created.id ])
    expect(price_rows.size).to eq(1)
  end

  it "既存の品目の今日の単価と違う単価は、単価を指す INVALID_INPUT で、品目も単価も変えない" do
    created = save.value

    result = save(name: "改名", unit_price: 350)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :unit_price ] ] ])
    expect(described_class.item(actor, created.id)).to have_attributes(name: "新品目", unit_price: 300)
    expect(price_rows.size).to eq(1)
  end

  it "公開した品目を保存しても、公開の状態を変えない" do
    item = save.value
    described_class.set_published(actor, item_id: item.id, published: true)

    expect(save(name: "改名").value).to have_attributes(id: item.id, published: true)
  end

  it "入力の誤りを、項目を指す INVALID_INPUT で返す" do
    failure = ->(result) { result.failures.map { [ _1.code, _1.path ] } }

    expect(failure.(save(tax_rate_percent: 5))).to eq([ [ :invalid_input, [ :tax_rate_percent ] ] ])
    expect(failure.(save(code: ""))).to eq([ [ :invalid_input, [ :code ] ] ])
    expect(failure.(save(unit_price: -1))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
    expect(described_class.items(actor, first: 10, after: nil).values).to be_empty
  end

  it "見えない品目の公開の状態は変えられず、品目 ID を指す NOT_FOUND を返す" do
    result = described_class.set_published(actor, item_id: SecureRandom.uuid, published: true)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :item_id ] ] ])
  end
end
