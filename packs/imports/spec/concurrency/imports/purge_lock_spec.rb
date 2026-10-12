require "rails_helper"

# 置いたままのファイルの後始末と取り込みの開始は、ファイルの行ロックで直列になる（docs/architecture/data-model.md「取り込み（`imports`）」）。
# 後始末は候補の行をロックしてから取り込みの有無を別の文で読み直すので、開始が先にコミットしたファイルの中身は残る。
# 開始は行をロックしてから中身の有無を読むので、後始末が先にコミットしたファイルへの開始は CONFLICT になる
RSpec.describe "置いたままのファイルの後始末と取り込みの開始" do
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let(:actor) { Tenancy.with_tenant(tenant) { Partnerships::Authentication.acting_user(admin.id) } }
  let(:csv) { "item_code,quantity\n" }
  # 置いてから 24 時間を過ぎ、後始末の候補になるファイル
  let!(:file) { travel_to(25.hours.ago) { tenancy { Imports::Files.store(actor, filename: "stocks.csv", content: csv).value } } }

  after { delete_owned_rows([ tenant ], %w[imports import_files]) }

  def tenancy(&) = Tenancy.with_tenant(tenant, &)
  def start = Imports::Runs.start(actor, Imports::Runs.request(actor, file_id: file.id, kind: "stocks"))
  def content = tenancy { Imports::ImportFile.find(file.id).content }
  def imports = tenancy { Imports::Import.where(import_file_id: file.id).count }

  it "後始末が先にロックすると、開始はそのコミットを待ってから、中身を消したファイルとして CONFLICT になる" do
    purged, release, holder = hold_open(tenant) { Imports::Files.purge_abandoned }
    waiter = in_thread(tenant) { start }

    expect(purged).to eq(1)
    expect(blocked_on_lock?(waiter, by: holder)).to be(true)
    commit(release, holder)
    expect(finish(waiter).failures.map { [ _1.code, _1.path, _1.message ] })
      .to eq([ [ :conflict, [ :file_id ], "This file was removed because it was not imported within 24 hours. Upload it again" ] ])
    expect([ content, imports ]).to eq([ nil, 0 ])
  end

  it "開始が先にロックすると、後始末はそのコミットを待ってから取り込みを読み直し、開始が成立したファイルの中身を残す" do
    started, release, holder = hold_open(tenant) { start }
    waiter = in_thread(tenant) { Imports::Files.purge_abandoned }

    expect(started).to be_success
    expect(blocked_on_lock?(waiter, by: holder)).to be(true)
    commit(release, holder)
    expect(finish(waiter)).to eq(0)
    expect([ content, imports ]).to eq([ csv, 1 ])
  end
end
