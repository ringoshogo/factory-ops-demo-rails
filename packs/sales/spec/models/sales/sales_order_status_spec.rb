require "rails_helper"

# 導出表の行ごとに 1 つ（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）
RSpec.describe Sales::SalesOrderStatus do
  let(:now) { Time.current }

  # モデルを作るだけでもテナントの設定が要る
  around { |example| Tenancy.with_tenant(FactoryBot.create(:tenant).id) { example.run } }
  let(:matched) { Sales::SalesOrderLine.new(id: SecureRandom.uuid, item_id: SecureRandom.uuid, quantity: 2) }
  let(:other) { Sales::SalesOrderLine.new(id: SecureRandom.uuid, item_id: SecureRandom.uuid, quantity: 3) }
  let(:unmatched) { Sales::SalesOrderLine.new(id: SecureRandom.uuid, quantity: 1) }

  def derive(lines, allocated: {}, **timestamps)
    described_class.derive(Sales::SalesOrder.new(**timestamps), lines, allocated:)
  end

  it "1. cancelled_at があれば、取消済" do
    expect(derive([ unmatched ], cancelled_at: now, inspected_at: now, shipped_at: now)).to eq(:cancelled)
  end

  it "2. inspected_at があれば、検収済" do
    expect(derive([ matched ], inspected_at: now, shipped_at: now)).to eq(:inspected)
  end

  it "3. shipped_at があれば、出荷済" do
    expect(derive([ matched ], shipped_at: now)).to eq(:shipped)
  end

  it "4. item_id が空の明細があれば、品番照合待ち" do
    expect(derive([ matched, unmatched ], allocated: { matched.id => 2 })).to eq(:awaiting_part_match)
  end

  it "5. 全明細が全量引き当て済みなら、引当済" do
    expect(derive([ matched, other ], allocated: { matched.id => 2, other.id => 3 })).to eq(:allocated)
  end

  it "6. 引当が 1 つ以上あれば、一部引当" do
    expect(derive([ matched, other ], allocated: { matched.id => 2 })).to eq(:partially_allocated)
  end

  it "7. それ以外は、受注済" do
    expect(derive([ matched, other ])).to eq(:received)
  end
end
