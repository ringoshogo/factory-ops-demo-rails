require "rails_helper"
require_relative "../../../../../spec/support/concurrency"

# 在庫の行がまだ無い品目を、2 つの取引が逆の並びで同時に lock_for へ渡しても、デッドロックしない
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」のロックの順）
RSpec.describe Inventory::Stock do
  self.use_transactional_tests = false

  let!(:tenant) { FactoryBot.create(:tenant) }
  let(:item_ids) { Array.new(2) { SecureRandom.uuid }.sort }

  after { delete_owned_rows([ tenant.id ], %w[stocks]) }

  # 1 つの INSERT の中で行の間に割り込めないので、挿入を 1 行ずつの INSERT に分け、行の間で止められるようにする。
  # 行を渡す順は lock_for が決めたままで、PostgreSQL が 1 つの INSERT の行を並びの順に入れるのと同じ待ち方になる
  def pause_between_inserted_rows(pauses)
    allow(described_class).to receive(:insert_all).and_wrap_original do |original, rows, **options|
      rows.each_with_index do |row, index|
        original.call([ row ], **options)
        pauses[Thread.current]&.call if index.zero?
      end
    end
  end

  it "片方が最初の品目の行を挿入した後に、もう片方が逆の並びで挿入に入っても、どちらも行ロックを得て終わる" do
    inserted_first = Queue.new
    resume = release_queue
    pauses = {}
    pause_between_inserted_rows(pauses)

    forward = in_thread(tenant.id) do
      pauses[Thread.current] = lambda do
        inserted_first << true
        resume.pop
      end
      described_class.lock_for(tenant.id, item_ids).keys
    end
    inserted_first.pop

    # 逆の並びの取引は、先の取引が挿入した行のコミットを、一意索引の上で待つ
    backward = in_thread(tenant.id) { described_class.lock_for(tenant.id, item_ids.reverse).keys }
    expect(blocked_on_lock?(backward, by: forward)).to be(true)
    resume << true

    expect([ finish(forward), finish(backward) ]).to eq([ item_ids, item_ids ])
    expect(Tenancy.with_tenant(tenant.id) { described_class.where(item_id: item_ids).count }).to eq(2)
  end
end
