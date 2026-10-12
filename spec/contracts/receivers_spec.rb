require "rails_helper"

# イベントの受け手は操作者のいない入口なので、テナントの設定を求め、値を返さない
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
RSpec.describe "イベントの受け手" do
  receivers = Contracts::Subscriptions::TABLE.values.flatten.map(&:receiver).uniq.sort

  receivers.each do |receiver|
    it "#{receiver} は、テナントの設定の外ではイベントを読まずに例外にする" do
      event = instance_double(Contracts::Event)

      expect { receiver.constantize.handle(event) }.to raise_error(Tenancy::MissingTenant)
    end
  end

  it "どの受け手も、受け取ったイベントを処理した後に値を返さない" do
    returned = Hash.new { |hash, key| hash[key] = [] }
    receivers.each do |receiver|
      allow(receiver.constantize).to receive(:handle).and_wrap_original { |original, event| original.call(event).tap { returned[receiver] << _1 } }
    end

    DemoWorld.build(namespace: "r#{SecureRandom.hex(3)}", variant: :seed)

    # 対照：シードの世界は、どの受け手にもイベントを届ける
    expect(returned.keys).to match_array(receivers)
    expect(returned.transform_values(&:uniq)).to eq(receivers.index_with { [ nil ] })
  end
end
