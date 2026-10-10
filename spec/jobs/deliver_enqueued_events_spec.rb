require "rails_helper"
require_relative "../support/tenant_helpers"
require_relative "../support/events"

# テストでイベントを流す補助（spec/support/events.rb）が、指定した順に受け手へ届ける。
# 届く順を入れ替えた example（docs/architecture/data-model.md「イベントの届く順の入れ替わり」）は、この補助が逆順に流すことを前提にする
RSpec.describe "deliver_enqueued_events" do
  include TenantHelpers

  let!(:tenant) { create_tenant("events-helper") }
  let(:received) { [] }

  before do
    stub_const("Contracts::SpecNumbered", Contracts::Event.define(:tenant_id, :number))
    log = received
    stub_const("SpecReceiver", Class.new { define_singleton_method(:handle) { |event| log << event.number } })
    stub_const("Contracts::Subscriptions::TABLE", {
      "Contracts::SpecNumbered" => [ Contracts::Subscriptions::Route.new(receiver: "SpecReceiver", tenant_key: "tenant_id") ]
    })
    Tenancy.with_tenant(tenant) { [ 1, 2, 3 ].each { Contracts.publish(Contracts::SpecNumbered.new(tenant_id: tenant, number: _1)) } }
  end

  it "既定では古い順に流す" do
    deliver_enqueued_events

    expect(received).to eq([ 1, 2, 3 ])
  end

  it "newest_first: true では新しい順に流す" do
    deliver_enqueued_events(newest_first: true)

    expect(received).to eq([ 3, 2, 1 ])
  end

  it "times: 2 では同じジョブを 2 回ずつ流す" do
    deliver_enqueued_events(times: 2)

    expect(received).to eq([ 1, 1, 2, 2, 3, 3 ])
  end
end
