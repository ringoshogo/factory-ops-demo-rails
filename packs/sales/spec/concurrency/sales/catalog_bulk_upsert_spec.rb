require "rails_helper"

# 取り込みの品目の書き込みの競合（docs/architecture/data-model.md「取り込み（`imports`）」）。同じ新しいコードを 2 つの取り込みが
# 並んで書いても、後の upsert は一意索引で先のコミットを待ってから更新に回るので、品目は 1 つで、最初の単価の行も 1 つになる
RSpec.describe Sales::Catalog, ".bulk_upsert" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "") }

  after { delete_owned_rows([ supplier.id ], %w[item_labels item_prices items]) }

  def row(name, unit_price) = { code: "NEW-1", name:, unit: "個", tax_rate_percent: 10, published: false, unit_price: }

  it "同じ新しいコードを 2 つの接続で同時に書いても、後の書き込みは先のコミットを待って更新になり、単価の行は先の 1 行だけになる" do
    first_result, release, first = hold_open(supplier.id) { described_class.bulk_upsert(actor, [ row("先", 100) ]) }
    second = in_thread(supplier.id) { described_class.bulk_upsert(actor, [ row("後", 200) ]) }

    expect(blocked_on_lock?(second, by: first)).to be(true)
    commit(release, first)
    second_result = finish(second)

    expect([ first_result, second_result ].map { _1.fetch("NEW-1").value.created }).to eq([ true, false ])
    Tenancy.with_tenant(supplier.id) do
      item = described_class.items(actor, first: 10, after: nil).values.sole
      expect([ item.name, item.unit_price ]).to eq([ "後", 100 ])
      expect(Sales::ItemPrices.history(actor, [ item.id ]).fetch(item.id).map(&:unit_price)).to eq([ 100 ])
    end
  end
end
