require "rails_helper"

# 置いたまま取り込まれないファイルの中身を、置いてから 24 時間を過ぎたら消す。定期のジョブがテナントを 1 つずつ開いて
# 公開 API を呼び、公開 API は所有の条件を明示して、取り込みを始めたファイルには触れない
# （docs/architecture/data-model.md「取り込み（`imports`）」）
RSpec.describe Imports::PurgeAbandonedFilesJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { FactoryBot.create(:tenant).id }
  let(:other) { FactoryBot.create(:tenant).id }
  let(:now) { Time.zone.parse("2026-10-12 10:00:00") }

  def actor(tenant_id)
    Tenancy.with_tenant(tenant_id) { Partnerships::Authentication.acting_user(FactoryBot.create(:user, :admin).id) }
  end

  # placed_at の時刻にファイルを置く
  def place(tenant_id, placed_at:)
    user = actor(tenant_id)
    travel_to(placed_at) do
      Tenancy.with_tenant(tenant_id) { Imports::Files.store(user, filename: "stocks.csv", content: "item_code,quantity\n").value }
    end
  end

  def content(tenant_id, file) = Tenancy.with_tenant(tenant_id) { Imports::ImportFile.find(file.id).content }

  # 時刻を同じ秒に揃えるため、置く時刻と流す時刻を now から決める
  it "置いてから 24 時間ちょうどのファイルは残し、24 時間 + 1 秒のファイルの中身を消す" do
    exact = place(tenant, placed_at: now - 24.hours)
    over = place(tenant, placed_at: now - 24.hours - 1.second)

    travel_to(now) { described_class.perform_now }

    expect([ content(tenant, exact), content(tenant, over) ]).to eq([ "item_code,quantity\n", nil ])
  end

  it "どのテナントの置いたままのファイルも消す" do
    files = [ tenant, other ].to_h { [ _1, place(_1, placed_at: now - 25.hours) ] }

    travel_to(now) { described_class.perform_now }

    expect(files.map { |tenant_id, file| content(tenant_id, file) }).to eq([ nil, nil ])
  end

  describe "Imports::Files.purge_abandoned" do
    it "取り込みを始めたファイルは消さず、同じ時刻に置いた始めていないファイルの中身を消して、消した件数を返す" do
      started = place(tenant, placed_at: now - 25.hours)
      abandoned = place(tenant, placed_at: now - 25.hours)
      user = actor(tenant)
      Tenancy.with_tenant(tenant) { Imports::Runs.start(user, Imports::Runs.request(user, file_id: started.id, kind: "stocks")) }

      count = travel_to(now) { Tenancy.with_tenant(tenant) { Imports::Files.purge_abandoned } }

      expect(count).to eq(1)
      expect([ content(tenant, started), content(tenant, abandoned) ]).to eq([ "item_code,quantity\n", nil ])
    end

    it "開いたテナントのファイルだけを消し、他社の置いたままのファイルには触れない" do
      mine = place(tenant, placed_at: now - 25.hours)
      theirs = place(other, placed_at: now - 25.hours)

      count = travel_to(now) { Tenancy.with_tenant(tenant) { Imports::Files.purge_abandoned } }

      expect(count).to eq(1)
      expect([ content(tenant, mine), content(other, theirs) ]).to eq([ nil, "item_code,quantity\n" ])
    end

    it "テナントを開かずに呼ぶと例外になる" do
      expect { Imports::Files.purge_abandoned }.to raise_error(Tenancy::MissingTenant)
    end
  end
end
