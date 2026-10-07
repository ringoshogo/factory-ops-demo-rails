require "rails_helper"

# 導出表の行ごとに 1 つ（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）
RSpec.describe Purchasing::PurchaseOrderStatus do
  let(:now) { Time.current }

  # モデルを作るだけでもテナントの設定が要る
  around { |example| Tenancy.with_tenant(FactoryBot.create(:tenant).id) { example.run } }

  def order(**timestamps)
    Purchasing::PurchaseOrder.new(**timestamps)
  end

  it "1. supplier_cancelled_at があれば、受注側により取消" do
    expect(described_class.derive(order(supplier_cancelled_at: now, accepted_at: now), inbound: true, inspected: true))
      .to eq(:supplier_cancelled)
  end

  it "2. cancelled_at があれば、取消済み" do
    expect(described_class.derive(order(cancelled_at: now, accepted_at: now), inbound: true, inspected: true)).to eq(:cancelled)
  end

  it "3. 入荷に検収があれば、検収済" do
    expect(described_class.derive(order(accepted_at: now), inbound: true, inspected: true)).to eq(:inspected)
  end

  it "4. 入荷があれば、入荷予定" do
    expect(described_class.derive(order(accepted_at: now), inbound: true)).to eq(:inbound)
  end

  # 照合待ちの後で照合でき、受注確定が届いた発注も受注済になる
  it "5. accepted_at があれば、受注済" do
    expect(described_class.derive(order(accepted_at: now, awaiting_match_at: now))).to eq(:accepted)
  end

  it "6. awaiting_match_at があれば、受注側で確認中" do
    expect(described_class.derive(order(awaiting_match_at: now))).to eq(:awaiting_supplier_confirmation)
  end

  it "7. それ以外は、送信済み" do
    expect(described_class.derive(order)).to eq(:sent)
  end
end
