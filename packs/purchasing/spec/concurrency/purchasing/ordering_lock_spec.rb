require "rails_helper"
require Rails.root.join("spec/support/owner_connection").to_s

# 発注の登録と、取引関係の失効・権限の撤回が並んだときの順序（docs/architecture/context-map.md「取引関係の失効」）。
# 2 つの接続を別のスレッドで動かし、一方のトランザクションを開いたまま他方を走らせる。
# 例ごとのトランザクションの中では接続が 1 本に固定されるので、使わず、作った行は所有ロールで消す
RSpec.describe "発注の登録と取引関係の失効の競合" do
  self.use_transactional_tests = false

  let!(:supplier) { FactoryBot.create(:tenant, code: "ordering-lock-#{SecureRandom.hex(6)}") }
  let!(:buyer) { FactoryBot.create(:tenant, code: "ordering-lock-#{SecureRandom.hex(6)}") }
  let!(:partnership) do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:partnership, buyer_tenant_id: buyer.id, permissions: %w[place_orders]) }
  end

  after do
    # 期待が外れて途中で抜けても、開いたままのトランザクションを閉じてから消す
    @releases&.each { _1 << true }
    @threads&.each { _1.join(10) }
    connection = OwnerConnection.lease_connection
    tenants = [ supplier.id, buyer.id ].map { connection.quote(_1) }.join(", ")
    connection.transaction do
      %w[purchase_order_lines purchase_orders purchase_order_sequences partnership_grants partnerships].each do |table|
        connection.execute("DELETE FROM #{table} WHERE owner_tenant_id IN (#{tenants})")
      end
      connection.execute("DELETE FROM solid_queue_jobs WHERE arguments LIKE #{connection.quote("%#{buyer.id}%")}")
      connection.execute("DELETE FROM tenants WHERE id IN (#{tenants})")
    end
  end

  def actor_of(tenant)
    Partnerships::Actor.new(user_id: nil, tenant_id: tenant.id, name: "", email: "", role: "admin", partner_code: "")
  end

  def place
    Purchasing::Ordering.place(actor_of(buyer), supplier_tenant_id: supplier.id, lines: [ { part_number: "P-1", quantity: 1 } ])
  end

  def revoke = Partnerships::Management.revoke(actor_of(supplier), partnership_id: partnership.id)

  def withdraw = Partnerships::Management.withdraw(actor_of(supplier), partnership_id: partnership.id, permission: "place_orders")

  # 別のスレッドでテナントのトランザクションを開いてブロックを実行し、結果を返す。コミットは release に値を積むまで止める
  def hold_open(tenant, &block)
    ready = Queue.new
    release = Queue.new
    thread = Thread.new do
      Tenancy.with_tenant(tenant.id) do
        ready << block.call
        release.pop
      end
    rescue StandardError => e
      ready << e
    end
    (@releases ||= []) << release
    (@threads ||= []) << thread
    result = ready.pop
    raise result if result.is_a?(Exception)

    [ result, release, thread ]
  end

  def in_thread(tenant, &block)
    Thread.new { Tenancy.with_tenant(tenant.id, &block) }.tap do |thread|
      thread.report_on_exception = false
      (@threads ||= []) << thread
    end
  end

  # スレッドが終わる前にロックの待ちに入れば真、待たずに終われば偽
  def blocked_on_lock?(thread)
    50.times do
      return false unless thread.alive?

      waiting = ApplicationRecord.with_connection do |connection|
        connection.select_value(<<~SQL)
          SELECT count(*) FROM pg_stat_activity
          WHERE datname = current_database() AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()
        SQL
      end
      return true if waiting.positive?

      sleep 0.1
    end
    raise "スレッドがロックを待たずに止まっている"
  end

  def purchase_order_count
    Tenancy.with_tenant(buyer.id) { ApplicationRecord.lease_connection.select_value("SELECT count(*) FROM purchase_orders") }
  end

  it "発注の登録がコミットするまで失効は待ち、失効の前に登録した発注は残る" do
    placed, release, placer = hold_open(buyer) { place }
    expect(placed).to be_success

    revoker = in_thread(supplier) { revoke }
    expect(blocked_on_lock?(revoker)).to be(true)

    release << true
    placer.join
    expect(revoker.value).to be_success
    expect(purchase_order_count).to eq(1)
  end

  { "失効" => :revoke, "place_orders の撤回" => :withdraw }.each do |name, operation|
    it "#{name}がコミットするまで発注の登録は待ち、コミットの後は NOT_PERMITTED になる" do
      changed, release, changer = hold_open(supplier) { send(operation) }
      expect(changed).to be_success

      placer = in_thread(buyer) { place }
      expect(blocked_on_lock?(placer)).to be(true)

      release << true
      changer.join
      expect(placer.value.failures.map(&:code)).to eq([ :not_permitted ])
      expect(purchase_order_count).to eq(0)
    end
  end
end
