require "rails_helper"

# 発注の登録と、取引関係の失効・権限の撤回が並んだときの順序（docs/architecture/context-map.md「取引関係の失効」）。
# 2 つの接続を別のスレッドで動かし、一方のトランザクションを開いたまま他方を走らせる
RSpec.describe "発注の登録と取引関係の失効の競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant, code: "ordering-lock-#{SecureRandom.hex(6)}") }
  let!(:buyer) { FactoryBot.create(:tenant, code: "ordering-lock-#{SecureRandom.hex(6)}") }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end

  after do
    delete_owned_rows([ supplier.id, buyer.id ],
      %w[purchase_order_lines purchase_orders purchase_order_sequences partnership_grants partnerships])
  end

  def actor_of(tenant)
    Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "admin", partner_code: "")
  end

  def place
    Purchasing::Ordering.place(actor_of(buyer), supplier_tenant_id: supplier.id, lines: [ { part_number: "P-1", quantity: 1 } ])
  end

  def revoke = Partnerships::Management.revoke(actor_of(supplier), partnership_id: partnership.id)

  def withdraw = Partnerships::Management.withdraw(actor_of(supplier), partnership_id: partnership.id, permission: "place_orders")

  def purchase_order_count
    Tenancy.with_tenant(buyer.id) { ApplicationRecord.lease_connection.select_value("SELECT count(*) FROM purchase_orders") }
  end

  it "発注の登録がコミットするまで失効は待ち、失効の前に登録した発注は残る" do
    placed, release, placer = hold_open(buyer.id) { place }
    expect(placed).to be_success

    revoker = in_thread(supplier.id) { revoke }
    expect(blocked_on_lock?(revoker, by: placer)).to be(true)

    expect(commit(release, placer)).to be_success
    expect(finish(revoker)).to be_success
    expect(purchase_order_count).to eq(1)
  end

  { "失効" => :revoke, "place_orders の撤回" => :withdraw }.each do |name, operation|
    it "#{name}がコミットするまで発注の登録は待ち、コミットの後は NOT_PERMITTED になる" do
      changed, release, changer = hold_open(supplier.id) { send(operation) }
      expect(changed).to be_success

      placer = in_thread(buyer.id) { place }
      expect(blocked_on_lock?(placer, by: changer)).to be(true)

      expect(commit(release, changer)).to be_success
      expect(finish(placer).failures.map(&:code)).to eq([ :not_permitted ])
      expect(purchase_order_count).to eq(0)
    end
  end
end
