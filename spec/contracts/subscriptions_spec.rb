require "rails_helper"

# 配送表は受け手を文字列で書くので、名前の誤りは実行するまで分からない。ここで先に落とす
RSpec.describe Contracts::Subscriptions do
  described_class::TABLE.each do |event_name, routes|
    describe event_name do
      it "イベントの型が Contracts::Event から作られている" do
        expect(event_name.safe_constantize).to be < Contracts::Event
      end

      routes.each do |route|
        it "受け手 #{route.receiver} が定数として存在し、handle を持つ" do
          expect(route.receiver.safe_constantize).to respond_to(:handle)
        end

        it "宛先 #{route.tenant_key} がイベントの項目である" do
          expect(event_name.constantize.members).to include(route.tenant_key.to_sym)
        end
      end
    end
  end

  it "表が Route だけを並べている" do
    expect(described_class::TABLE.values.flatten).to all(be_a(described_class::Route))
  end
end
