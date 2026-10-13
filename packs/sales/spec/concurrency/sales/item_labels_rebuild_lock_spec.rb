require "rails_helper"

# 品目の写しの作り直しと品目の保存の競合（docs/adr/011 決定 1）。作り直しは品目を FOR SHARE で読むので、品目を読んだ後の保存は
# 作り直しのコミットを待つ。待たないと、作り直しが読んだ古い名前で、保存が書いた新しい名前の写しを上書きする
RSpec.describe Sales::Catalog, ".rebuild_item_labels" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  after { delete_owned_rows([ supplier.id ], %w[item_labels item_prices items]) }

  def save(name) = described_class.save(actor, code: "N-1", name:, unit: "個", unit_price: 100, tax_rate_percent: 10)

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
    read.pop
    saver = in_thread(supplier.id) { save("新しい名前") }
    waited = blocked_on_lock?(saver, by: rebuilder)

    resume << true
    finish(rebuilder)
    expect(finish(saver)).to be_success
    labels = Tenancy.with_tenant(supplier.id) { ActiveRecord::Base.lease_connection.select_rows("SELECT item_id, name FROM item_labels") }
    expect(labels).to eq([ [ item.id, "新しい名前" ] ])
    expect(waited).to be(true)
  end
end
