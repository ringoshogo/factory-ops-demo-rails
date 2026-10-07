require "rails_helper"

# 導出表の行ごとに 1 つ（docs/architecture/data-model.md「状態は保存せず、時刻列から導出する」）。「出荷停止中」は M15 で足す
RSpec.describe Fulfillment::ShipmentRequestStatus do
  # モデルを作るだけでもテナントの設定が要る
  around { |example| Tenancy.with_tenant(FactoryBot.create(:tenant).id) { example.run } }

  def derive(instructed: false, shipped: false, **timestamps)
    described_class.derive(Fulfillment::ShipmentRequest.new(**timestamps), instructed:, shipped:)
  end

  it "1. cancelled_at があれば、取消済" do
    expect(derive(cancelled_at: Time.current, instructed: true, shipped: true)).to eq(:cancelled)
  end

  it "2. 出荷実績があれば、出荷済" do
    expect(derive(instructed: true, shipped: true)).to eq(:shipped)
  end

  it "4. 有効な出荷指示があれば、出荷指示済" do
    expect(derive(instructed: true)).to eq(:instructed)
  end

  it "5. それ以外は、出荷待ち" do
    expect(derive).to eq(:ready)
  end
end
