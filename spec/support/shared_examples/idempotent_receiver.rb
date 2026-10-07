require_relative "../events"

# 受け手の冪等の確かめ方（docs/architecture/data-model.md「イベントの受け口と冪等キー」）。
# 使う側は、Contracts.publish でイベントを登録する publish_event と、受け手が書いた行を数える written_rows を let で渡す。
# どちらも Tenancy.with_tenant の外で呼ばれる
RSpec.shared_examples "冪等な受け手" do
  it "同じイベントが 2 回届いても、書いた行は 1 回分である" do
    publish_event.call
    deliver_enqueued_events
    once = written_rows.call

    publish_event.call
    deliver_enqueued_events(times: 2)

    expect(once).to be_positive
    expect(written_rows.call).to eq(once)
  end
end
