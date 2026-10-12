require "rails_helper"

# ダッシュボードの安全在庫。有効在庫（現在庫 - 引当）が安全在庫より小さい在庫だけを返し、等しい在庫は返さない
# （docs/architecture/data-model.md「在庫（`inventory`）」、docs/architecture/graphql-schema.md「読み取りの一覧」）
RSpec.describe Inventory::Stocks do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  def below_safety_stock = Tenancy.with_tenant(supplier.id) { described_class.below_safety_stock(actor) }

  describe ".below_safety_stock" do
    it "有効在庫が安全在庫より 1 小さい在庫を返し、等しい在庫と大きい在庫を返さない。引当を差し引いて比べる" do
      below, equal, above, allocated_below = Tenancy.with_tenant(supplier.id) do
        [ FactoryBot.create(:stock, on_hand: 4, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 5, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 6, safety_stock: 5),
          FactoryBot.create(:stock, on_hand: 10, allocated: 6, safety_stock: 5) ]
      end

      expect(below_safety_stock.map(&:item_id)).to match_array([ below.item_id, allocated_below.item_id ])
      expect(below_safety_stock).to all(have_attributes(below_safety_stock: true))
      expect([ equal, above ].map(&:item_id) & below_safety_stock.map(&:item_id)).to be_empty
    end

    it "他社の在庫を返さない" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }
      Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, on_hand: 0, safety_stock: 1) }

      # 対照：同じ条件の自社の在庫は返る
      expect(below_safety_stock.map(&:item_id)).to eq([ own.item_id ])
    end
  end

  # シードと E2E の世界の準備のための安全在庫の設定。自社の在庫の行だけを変え、数量と移動履歴には触れない。
  # 本番の環境では呼べない（docs/architecture/graphql-schema.md「認可」）
  describe ".set_safety_stock" do
    let!(:own) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:stock, on_hand: 10, safety_stock: 3) } }
    let!(:theirs) { Tenancy.with_tenant(other.id) { FactoryBot.create(:stock, on_hand: 10, safety_stock: 3) } }

    def set(item_id, safety_stock) = Tenancy.with_tenant(supplier.id) { described_class.set_safety_stock(actor, item_id:, safety_stock:) }

    def failures(result) = result.failures.map { [ _1.code, _1.path ] }

    # アプリのロールの接続で、テナントを設定して生 SQL で読む。RLS が、設定したテナントの行だけを見せる
    def safety_stock_seen_by(tenant, item_id)
      Tenancy.with_tenant(tenant.id) do
        ActiveRecord::Base.lease_connection.select_value("SELECT safety_stock FROM stocks WHERE item_id = $1", "SQL", [ item_id ])
      end
    end

    it "自社の在庫の安全在庫を変え、数量と移動履歴は変えない" do
      result = set(own.item_id, 12)

      expect(result.value).to have_attributes(item_id: own.item_id, on_hand: 10, safety_stock: 12, below_safety_stock: true)
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(12)
      expect(Tenancy.with_tenant(supplier.id) { Inventory::StockMovement.where(item_id: own.item_id).count }).to eq(0)
    end

    it "今と同じ値も成功し、何も変えない" do
      expect(set(own.item_id, 3).value).to have_attributes(item_id: own.item_id, safety_stock: 3)
      expect(set(own.item_id, 12)).to be_success
      expect(set(own.item_id, 12).value).to have_attributes(safety_stock: 12, on_hand: 10)
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(12)
    end

    it "他社の品目は NOT_FOUND で、他社の在庫を書かない" do
      expect(failures(set(theirs.item_id, 99))).to eq([ [ :not_found, [ :item_id ] ] ])
      # 対照：他社の設定の生 SQL は他社の在庫を読み、値は元のままである
      expect(safety_stock_seen_by(other, theirs.item_id)).to eq(3)
      expect(safety_stock_seen_by(supplier, theirs.item_id)).to be_nil
    end

    it "在庫の行の無い品目は NOT_FOUND で、行を作らない" do
      item_id = SecureRandom.uuid

      expect(failures(set(item_id, 1))).to eq([ [ :not_found, [ :item_id ] ] ])
      expect(safety_stock_seen_by(supplier, item_id)).to be_nil
    end

    it "安全在庫は 0 と 2,147,483,647 ちょうどを受け付け、負と 2,147,483,648 と整数でない値は INVALID_INPUT で何も書かない" do
      expect([ -1, 2_147_483_648, 1.5, "3" ].map { failures(set(own.item_id, _1)) }).to all(eq([ [ :invalid_input, [ :safety_stock ] ] ]))
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(3)

      expect(set(own.item_id, 0)).to be_success
      expect(set(own.item_id, 2_147_483_647)).to be_success
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(2_147_483_647)
    end

    it "本番の環境では、何も書かずに例外にする" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

      expect { set(own.item_id, 12) }.to raise_error(Inventory::Stocks::ProductionEnvironment)
      expect(safety_stock_seen_by(supplier, own.item_id)).to eq(3)
    end
  end
end
