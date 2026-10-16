require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 在庫の一覧を並べ、検索するための品目の写し（docs/architecture/data-model.md「在庫（`inventory`）」）。
# 写しを書く put は操作者のいない入口で、所有テナントを Current のテナントで明示して書き、他社の写しに当たらない
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
RSpec.describe Inventory::ItemLabels do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:actor) { Partnerships::Actor.new(user_id: nil, tenant_id: supplier.id, name: "", email: "", role: "member", partner_code: "") }

  def put(labels) = Tenancy.with_tenant(supplier.id) { described_class.put(labels) }

  # テナントごとの写しを、品目 ID => [コード, 名前] で読む
  def labels_of(tenant) = Tenancy.with_tenant(tenant.id) { Inventory::ItemLabel.pluck(:item_id, :code, :name).to_h { [ _1, [ _2, _3 ] ] } }

  describe ".put" do
    let(:bolt) { SecureRandom.uuid }
    let(:nut) { SecureRandom.uuid }

    it "無い写しを足し、値の違う写しを書き直し、値の同じ写しは書き直さずに、足した数と書き直した数を返す" do
      expect(put([ { item_id: bolt, code: "B-1", name: "ボルト" } ])).to eq(described_class::Counts.new(inserted: 1, updated: 0))
      written_at = Tenancy.with_tenant(supplier.id) { Inventory::ItemLabel.find_by!(item_id: bolt).updated_at }

      counts = put([ { item_id: nut, code: "N-1", name: "ナット" }, { item_id: bolt, code: "B-1", name: "ボルト" } ])
      expect(counts).to eq(described_class::Counts.new(inserted: 1, updated: 0))
      expect(Tenancy.with_tenant(supplier.id) { Inventory::ItemLabel.find_by!(item_id: bolt).updated_at }).to eq(written_at)

      counts = put([ { item_id: bolt, code: "B-1", name: "六角ボルト" }, { item_id: nut, code: "N-2", name: "ナット" } ])
      expect(counts).to eq(described_class::Counts.new(inserted: 0, updated: 2))
      expect(labels_of(supplier)).to eq(bolt => [ "B-1", "六角ボルト" ], nut => [ "N-2", "ナット" ])
      expect(put([])).to eq(described_class::Counts.new(inserted: 0, updated: 0))
    end

    it "足した数と書き直した数を、それぞれ足し合わせる" do
      sum = described_class::Counts.new(inserted: 1, updated: 2) + described_class::Counts.new(inserted: 3, updated: 5)

      expect(sum).to eq(described_class::Counts.new(inserted: 4, updated: 7))
    end

    it "テナントの設定の外では例外にし、何も書かない" do
      expect { described_class.put([ { item_id: bolt, code: "B-1", name: "ボルト" } ]) }.to raise_error(Tenancy::MissingTenant)
      expect(labels_of(supplier)).to be_empty
    end

    it "他社の名義で同じ品目 ID の写しがあっても、自社の写しを足し、他社の写しを変えない" do
      Tenancy.with_tenant(other.id) { FactoryBot.create(:item_label, item_id: bolt, code: "X-1", name: "他社の品目") }

      expect(put([ { item_id: bolt, code: "B-1", name: "ボルト" } ])).to eq(described_class::Counts.new(inserted: 1, updated: 0))
      expect(labels_of(supplier)).to eq(bolt => [ "B-1", "ボルト" ])
      expect(labels_of(other)).to eq(bolt => [ "X-1", "他社の品目" ])
    end
  end

  describe ".find" do
    it "自社の写しを値で返し、他社の写しの品目 ID と写しの無い品目 ID は nil を返す" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item_label, code: "B-1", name: "ボルト") }
      theirs = Tenancy.with_tenant(other.id) { FactoryBot.create(:item_label) }

      Tenancy.with_tenant(supplier.id) do
        expect(described_class.find(actor, own.item_id))
          .to eq(Inventory::ItemLabelValue.new(owner_tenant_id: supplier.id, item_id: own.item_id, code: "B-1", name: "ボルト"))
        expect(described_class.find(actor, theirs.item_id)).to be_nil
        expect(described_class.find(actor, SecureRandom.uuid)).to be_nil
      end
    end
  end

  # RLS が他社の写しを隠すので、所有の条件を外しても上の example は落ちない。RLS の SELECT と UPDATE を開き、
  # 他社の写しが見え、更新の対象に入る状態で確かめる（docs/guides/testing.md「行列テストとの分担」）
  describe "RLS の SELECT と UPDATE を開いたとき" do
    include_context "RLS の SELECT と UPDATE を開く"

    let(:item_id) { SecureRandom.uuid }
    let!(:theirs) { Tenancy.with_tenant(other.id) { FactoryBot.create(:item_label, item_id:, code: "A-1", name: "他社の品目") } }

    it "put は、他社の名義で同じ品目 ID の写しがあっても、他社の写しを所有の列を含めて変えない" do
      Tenancy.with_tenant(supplier.id) do
        cross_read!
        # 対照：開いた後は他社の写しが見え、自社の写しは足して書き直す
        before = reread(theirs)
        expect(Inventory::ItemLabel.where(item_id:).pluck(:owner_tenant_id)).to eq([ other.id ])
        expect(described_class.put([ { item_id:, code: "B-1", name: "ボルト" } ])).to eq(described_class::Counts.new(inserted: 1, updated: 0))
        expect(described_class.put([ { item_id:, code: "B-1", name: "六角ボルト" } ])).to eq(described_class::Counts.new(inserted: 0, updated: 1))

        expect(Inventory::ItemLabel.where(item_id:).pluck(:owner_tenant_id, :name))
          .to contain_exactly([ supplier.id, "六角ボルト" ], [ other.id, "他社の品目" ])
        expect(reread(theirs)).to eq(before)
      end
    end

    it "find は、見えるようになった他社の写しの品目 ID にも nil を返す" do
      own = Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item_label) }

      Tenancy.with_tenant(supplier.id) do
        cross_read!
        # 対照：開いた後は他社の写しが見え、自社の写しは返る
        expect(Inventory::ItemLabel.where(item_id:).pluck(:owner_tenant_id)).to eq([ other.id ])
        expect(described_class.find(actor, own.item_id)&.item_id).to eq(own.item_id)

        expect(described_class.find(actor, item_id)).to be_nil
      end
    end

    # 品目 ID は UUIDv7 で他社の品目と重ならないので、写しを結ぶ条件から所有テナントを外しても入口の行列では捕まらない。
    # 他社の名義で自社の在庫の品目 ID を指す写しを作り、それを並びと検索に使わないことを、ここだけが確かめる
    it "在庫の一覧は、他社の名義で自社の在庫の品目 ID を指す写しを、並びと keyword の検索に使わない" do
      own, unlabeled = Tenancy.with_tenant(supplier.id) do
        own = FactoryBot.create(:stock).tap { FactoryBot.create(:item_label, item_id: _1.item_id, code: "M-1", name: "自社の品目") }
        [ own, FactoryBot.create(:stock, item_id:) ]
      end

      Tenancy.with_tenant(supplier.id) do
        cross_read!
        # 対照：開いた後は、自社の在庫の品目 ID を指す他社の写しが見え、自社の写しは検索に当たる
        expect(Inventory::ItemLabel.where(item_id: unlabeled.item_id).pluck(:owner_tenant_id)).to eq([ other.id ])
        expect(list(filter: { keyword: "自社" })).to eq([ [ own.item_id ], 1 ])

        expect(list(filter: { keyword: "他社" })).to eq([ [], 0 ])
        # 他社の写しの A-1 を使うと、写しの無い在庫が自社の M-1 より前に並ぶ
        expect(list(order_by: [ { field: :item_code, direction: :asc } ])).to eq([ [ own.item_id, unlabeled.item_id ], 2 ])
      end
    end

    def list(**options)
      page = Inventory::Stocks.list(actor, first: 10, after: nil, **options)
      [ page.values.map(&:item_id), page.total_count ]
    end
  end
end
