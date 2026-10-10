require "rails_helper"

# 受注側の品目の保存。品目コードで引き、無ければ非公開で作り、あれば更新する。公開の状態は set_published だけが変える
# （docs/architecture/graphql-schema.md「mutation の一覧」）
RSpec.describe Sales::Catalog do
  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

  def save(code: "N-1", name: "新品目", unit: "個", unit_price: 300, tax_rate_percent: 10)
    described_class.save(actor, code:, name:, unit:, unit_price:, tax_rate_percent:)
  end

  it "新しいコードなら非公開で作り、同じコードなら同じ品目を更新する" do
    created = save.value
    expect(created).to have_attributes(code: "N-1", name: "新品目", unit_price: 300, tax_rate_percent: 10, published: false)

    updated = save(name: "改名", unit_price: 350, tax_rate_percent: 8).value

    expect(updated).to have_attributes(id: created.id, name: "改名", unit_price: 350, tax_rate_percent: 8)
    expect(described_class.items(actor, first: 10, after: nil).values.map(&:id)).to eq([ created.id ])
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
    expect(described_class.items(actor, first: 10, after: nil).values).to be_empty
  end

  it "見えない品目の公開の状態は変えられず、品目 ID を指す NOT_FOUND を返す" do
    result = described_class.set_published(actor, item_id: SecureRandom.uuid, published: true)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :not_found, [ :item_id ] ] ])
  end
end
