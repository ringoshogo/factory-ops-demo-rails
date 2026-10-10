require "rails_helper"
require_relative "../../../../../spec/support/owner_connection"

# 在庫の行がまだ無い品目を、2 つの取引が逆の並びで同時に lock_for へ渡しても、デッドロックしない
# （docs/architecture/data-model.md「取消と出荷の競合を止める場所」のロックの順）。
# 2 つの接続で同時に動かすので、例ごとのトランザクションを使わず、作った行は例の後で所有ロールで消す
RSpec.describe Inventory::Stock do
  self.use_transactional_tests = false

  let!(:tenant) { FactoryBot.create(:tenant) }
  let(:item_ids) { Array.new(2) { SecureRandom.uuid }.sort }

  after do
    # 期待が外れて途中で抜けても、止めたままのスレッドを進め、スレッドの例外は例の中で確かめ済みなので捨てて消す
    @resume&.<< true
    @threads&.each do |thread|
      thread.join(10)
    rescue StandardError
      nil
    end
    connection = OwnerConnection.lease_connection
    connection.execute("DELETE FROM stocks WHERE owner_tenant_id = #{connection.quote(tenant.id)}")
    connection.execute("DELETE FROM tenants WHERE id = #{connection.quote(tenant.id)}")
  end

  def in_thread(&block)
    Thread.new { Tenancy.with_tenant(tenant.id, &block) }.tap do |thread|
      thread.report_on_exception = false
      (@threads ||= []) << thread
    end
  end

  def waiting_for_lock?
    ActiveRecord::Base.lease_connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    ).positive?
  end

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
    @resume = Queue.new
    pauses = {}
    pause_between_inserted_rows(pauses)

    forward = in_thread do
      pauses[Thread.current] = lambda do
        inserted_first << true
        @resume.pop
      end
      described_class.lock_for(tenant.id, item_ids).keys
    end
    inserted_first.pop

    # 逆の並びの取引は、先の取引が挿入した行のコミットを、一意索引の上で待つ
    backward = in_thread { described_class.lock_for(tenant.id, item_ids.reverse).keys }
    deadline = 5.seconds.from_now
    sleep 0.01 until !backward.alive? || waiting_for_lock? || Time.current > deadline
    expect(waiting_for_lock?).to be(true)
    @resume << true

    expect([ forward.value, backward.value ]).to eq([ item_ids, item_ids ])
    expect(Tenancy.with_tenant(tenant.id) { described_class.where(item_id: item_ids).count }).to eq(2)
  end
end
