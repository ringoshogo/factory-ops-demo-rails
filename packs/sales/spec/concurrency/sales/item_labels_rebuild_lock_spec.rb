require "rails_helper"

# 品目の写しの作り直しと品目の保存の競合（docs/adr/011 決定 1）。作り直しは品目を FOR SHARE で読むので、品目を読んだ後の保存は
# 作り直しのコミットを待つ。待たないと、作り直しが読んだ古い名前で、保存が書いた新しい名前の写しを上書きする
RSpec.describe Sales::Catalog, ".rebuild_item_labels" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  after { delete_owned_rows([ supplier.id ], %w[item_labels item_prices items]) }

  def save(name, code: "N-1") = described_class.save(actor, code:, name:, unit: "個", unit_price: 100, tax_rate_percent: 10)

  it "作り直しが品目を読んだ後の保存は、作り直しのコミットを待ってから書き、写しは保存した名前になる" do
    item = Tenancy.with_tenant(supplier.id) { save("古い名前").value }
    read = Queue.new
    resume = release_queue
    # 作り直しのスレッドだけを、品目を読んだ後、写しを書く前で止める
    allow(Inventory::ItemLabels).to receive(:put).and_wrap_original do |original, labels|
      if Thread.current[:pause_before_put]
        read << true
        resume.pop
      end
      original.call(labels)
    end

    rebuilder = in_thread(supplier.id) do
      Thread.current[:pause_before_put] = true
      described_class.rebuild_item_labels
    end
    # 作り直しが put の前に失敗するか、put を包めずに止まらなければ、ここで待ち続けずに失敗する
    raise "作り直しが #{ConcurrencyHelpers::WAIT_SECONDS} 秒で品目を読み終えない" unless read.pop(timeout: ConcurrencyHelpers::WAIT_SECONDS)
    saver = in_thread(supplier.id) { save("新しい名前") }
    waited = blocked_on_lock?(saver, by: rebuilder)

    resume << true
    finish(rebuilder)
    expect(finish(saver)).to be_success
    labels = Tenancy.with_tenant(supplier.id) { ActiveRecord::Base.lease_connection.select_rows("SELECT item_id, name FROM item_labels") }
    expect(labels).to eq([ [ item.id, "新しい名前" ] ])
    expect(waited).to be(true)
  end

  # 取り込み（bulk_upsert）は品目を Ruby の文字列の比べ方（バイトの順）でロックするので、作り直しも同じ順でロックしないと、
  # 2 つが逆の順で品目を取って行き詰まる。B-1 と a-1 は、バイトの順では B-1 が先で、DB の照合順序（en_US.utf8）では a-1 が先になる。
  # a-1 を保存が持つ間に作り直しを始め、作り直しが B-1 を先に取ってから a-1 を待つことを、B-1 の保存が作り直しを待つことで確かめる
  it "作り直しは、品目を取り込みと同じバイトの順でロックする" do
    Tenancy.with_tenant(supplier.id) { %w[B-1 a-1].each { save("名前", code: _1) } }
    expect(%w[a-1 B-1].sort).to eq(%w[B-1 a-1])

    _, release, holder = hold_open(supplier.id) { save("a-1 の新しい名前", code: "a-1") }
    rebuilder = in_thread(supplier.id) { described_class.rebuild_item_labels }
    expect(blocked_on_lock?(rebuilder, by: holder)).to be(true)

    saver = in_thread(supplier.id) { save("B-1 の新しい名前", code: "B-1") }
    expect(blocked_on_lock?(saver, by: rebuilder)).to be(true)

    commit(release, holder)
    finish(rebuilder)
    expect(finish(saver)).to be_success
  end
end
