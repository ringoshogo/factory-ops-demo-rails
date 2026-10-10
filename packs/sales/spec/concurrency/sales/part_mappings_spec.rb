require "rails_helper"
require_relative "../../../../../spec/support/concurrency"

# 受注を作る照合と対応表の登録が同時に進んでも、照合待ちの受注を見落とさない（Sales::PartMatching.lock）
RSpec.describe Sales::PartMappings do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:buyer) { FactoryBot.create(:tenant) }
  let!(:item) do
    Tenancy.with_tenant(supplier.id) do
      FactoryBot.create(:partnership, buyer_tenant_id: buyer.id)
      FactoryBot.create(:item)
    end
  end
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }
  let(:event) do
    Contracts::PurchaseOrderPlaced.new(purchase_order_id: SecureRandom.uuid, buyer_tenant_id: buyer.id, supplier_tenant_id: supplier.id,
      desired_delivery_on: nil, lines: [ { "purchase_order_line_id" => SecureRandom.uuid, "part_number" => "MY-BOLT", "quantity" => 1 } ])
  end

  after do
    delete_owned_rows([ supplier.id, buyer.id ],
      %w[sales_order_lines sales_orders sales_order_sequences customer_part_mappings items partnership_grants partnerships])
  end

  def statuses
    Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.list(actor, first: 10, after: nil).values.map(&:status) }
  end

  it "ACL が照合待ちの受注をコミットする前に登録しても、登録は ACL のコミットを待って照合し直す" do
    _, release, translator = hold_open(supplier.id) { Sales::PurchaseOrderTranslator.handle(event) }

    registering = in_thread(supplier.id) do
      described_class.register(actor, customer_tenant_id: buyer.id, customer_part_number: "MY-BOLT", item_id: item.id)
    end
    # 登録は、取引先ごとの advisory lock を待つ
    expect(blocked_on_lock?(registering, by: translator)).to be(true)

    commit(release, translator)
    expect(finish(registering)).to be_success
    expect(statuses).to eq([ :received ])
  end
end
