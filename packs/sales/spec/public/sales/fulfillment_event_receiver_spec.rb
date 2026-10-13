require "rails_helper"
require_relative "../../../../../spec/support/cross_read"
# 「出荷計上」の受注の受け手（docs/architecture/data-model.md「イベントの受け口と冪等キー」）。
# 配送表を通した重複配送は spec/contracts/shipment_posted_delivery_spec.rb が確かめる
RSpec.describe Sales::FulfillmentEventReceiver do
  include ActiveSupport::Testing::TimeHelpers

  let(:supplier) { FactoryBot.create(:tenant) }
  let(:buyer) { FactoryBot.create(:tenant) }
  let!(:order) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:sales_order, customer_tenant_id: buyer.id) } }
  let(:event) do
    Contracts::ShipmentPosted.new(shipment_id: SecureRandom.uuid, sales_order_id: order.id,
      purchase_order_id: order.source_purchase_order_id, supplier_tenant_id: supplier.id, buyer_tenant_id: buyer.id,
      shipped_on: "2026-10-09", lines: [])
  end

  def shipped_at = Tenancy.with_tenant(supplier.id) { order.reload.shipped_at }

  it "受注側テナントの名義で、受注に shipped_at を 1 回だけ書く" do
    Tenancy.with_tenant(supplier.id) { described_class.handle(event) }
    first = shipped_at

    travel 1.hour do
      Tenancy.with_tenant(supplier.id) { described_class.handle(event) }
    end

    expect(first).to be_present
    expect(shipped_at).to eq(first)
  end

  it "発注側テナントが一致しない受注は書かない" do
    other = event.with(buyer_tenant_id: FactoryBot.create(:tenant).id)

    expect { Tenancy.with_tenant(supplier.id) { described_class.handle(other) } }.to raise_error(ActiveRecord::RecordNotFound)
  end

  # イベントの受け手は操作者のいない入口なので、所有の条件を RLS に任せない。受注を FOR UPDATE で引くので、SELECT だけを開いても
  # RLS の UPDATE のポリシーが他社の受注を除き、条件の抜けが見えない（docs/guides/testing.md「行列テストとの分担」）
  describe "RLS の SELECT と UPDATE を開いたとき" do
    include_context "RLS の SELECT と UPDATE を開く"

    it "他社の受注は見つからず、書かない" do
      theirs = Tenancy.with_tenant(FactoryBot.create(:tenant).id) { FactoryBot.create(:sales_order, customer_tenant_id: buyer.id) }

      Tenancy.with_tenant(supplier.id) do
        cross_read!
        # 対照：開いた後は、他社の受注が見え、自社の受注には出荷済の時刻を書く
        before = reread(theirs)
        described_class.handle(event)
        expect(order.reload.shipped_at).to be_present

        expect { described_class.handle(event.with(sales_order_id: theirs.id, purchase_order_id: theirs.source_purchase_order_id)) }
          .to raise_error(ActiveRecord::RecordNotFound)
        expect(reread(theirs)).to eq(before)
      end
    end
  end

  it "配送表に無い種類のイベントは、受注を書かずに ArgumentError で失敗する" do
    unexpected = Contracts::PartMatchPending.new(purchase_order_id: order.source_purchase_order_id, buyer_tenant_id: buyer.id,
      supplier_tenant_id: supplier.id)

    expect { Tenancy.with_tenant(supplier.id) { described_class.handle(unexpected) } }
      .to raise_error(ArgumentError, "unexpected event: Contracts::PartMatchPending")
    expect(shipped_at).to be_nil
  end
end
