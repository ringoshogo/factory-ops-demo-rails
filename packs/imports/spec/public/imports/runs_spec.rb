require "rails_helper"

# 取り込みの開始・読み取り・再登録と、状況の導出（docs/architecture/data-model.md「取り込み（`imports`）」）
RSpec.describe Imports::Runs do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { FactoryBot.create(:tenant).id }
  let(:other) { FactoryBot.create(:tenant).id }
  let(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let(:member) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user) } }
  let(:actor) { Tenancy.with_tenant(tenant) { Partnerships::Authentication.acting_user(admin.id) } }

  def tenancy(id = tenant, &) = Tenancy.with_tenant(id, &)
  def jobs = SolidQueue::Job.where(class_name: "Imports::RunJob", finished_at: nil).where("arguments LIKE ?", "%#{tenant}%")

  def place(content = "item_code,quantity\n") = tenancy { Imports::Files.store(actor, filename: "stocks.csv", content:).value }

  describe ".start" do
    it "自社のファイルの取り込みを待機中で作り、取り込み ID とテナント ID を引数にしたジョブを登録する" do
      file = place
      import = tenancy { described_class.start(actor, described_class.request(actor, file_id: file.id, kind: "stocks")).value }

      expect(import).to have_attributes(kind: "stocks", status: :queued, applied_rows: 0, failed_rows: 0, total_rows: nil)
      expect(jobs.sole.arguments.values_at("arguments", "queue_name")).to eq([ [ import.id, tenant ], "imports" ])
      expect(tenancy { Imports::Import.find(import.id).requested_by_user_id }).to eq(admin.id)
    end

    it "同じファイルの 2 回目はファイル ID を指す CONFLICT で、取り込みもジョブも足さない" do
      request = tenancy { described_class.request(actor, file_id: place.id, kind: "stocks") }
      tenancy { described_class.start(actor, request) }

      result = tenancy { described_class.start(actor, request) }

      expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :conflict, [ :file_id ] ] ])
      expect([ tenancy { Imports::Import.count }, jobs.count ]).to eq([ 1, 1 ])
    end

    it "置いたまま中身を消したファイルは、ファイル ID を指して置き直しを促す CONFLICT で、取り込みもジョブも足さない" do
      abandoned = travel_to(25.hours.ago) { place }
      expect(tenancy { Imports::Files.purge_abandoned }).to eq(1)

      result = tenancy { described_class.start(actor, described_class.request(actor, file_id: abandoned.id, kind: "stocks")) }

      expect(result.failures.map { [ _1.code, _1.path, _1.message ] })
        .to eq([ [ :conflict, [ :file_id ], "This file was removed because it was not imported within 24 hours. Upload it again" ] ])
      expect([ tenancy { Imports::Import.count }, jobs.count ]).to eq([ 0, 0 ])
    end

    # 取り込みを終えたファイルも中身が空なので、取り込み済みを中身の有無より先に答える
    it "取り込みを終えて中身を消したファイルの 2 回目は、取り込み済みの CONFLICT になる" do
      request = tenancy { described_class.request(actor, file_id: place.id, kind: "stocks") }
      tenancy { described_class.start(actor, request) }
      tenancy { Imports::ImportFile.where(id: request.file_id).update_all(content: nil) }

      result = tenancy { described_class.start(actor, request) }

      expect(result.failures.map { [ _1.code, _1.message ] }).to eq([ [ :conflict, "This file has already been imported" ] ])
    end
  end

  describe ".request" do
    it "他社のファイルと存在しないファイルは nil で、自社のファイルは種類を持つ依頼になる" do
      theirs = tenancy(other) { FactoryBot.create(:import_file) }
      mine = place

      expect(tenancy { [ theirs.id, SecureRandom.uuid ].map { described_class.request(actor, file_id: _1, kind: "items") } }).to eq([ nil, nil ])
      expect(tenancy { described_class.request(actor, file_id: mine.id, kind: "items") })
        .to eq(Imports::ImportRequestValue.new(file_id: mine.id, owner_tenant_id: tenant, kind: "items"))
    end
  end

  describe Imports::ImportPolicy do
    def start?(user, kind) = Imports::ImportPolicy.new(Imports::ImportRequestValue.new(file_id: "f", owner_tenant_id: tenant, kind:),
      user: tenancy { Partnerships::Authentication.acting_user(user.id) }).apply(:start?)

    it "品目の取り込みは admin だけが始められ、在庫の取り込みは役割を問わない" do
      expect([ start?(admin, "items"), start?(member, "items"), start?(admin, "stocks"), start?(member, "stocks") ])
        .to eq([ true, false, true, true ])
    end

    it "他社の依頼は、admin でも始められない" do
      stranger = tenancy(other) { FactoryBot.create(:user, :admin) }
      user = tenancy(other) { Partnerships::Authentication.acting_user(stranger.id) }
      request = Imports::ImportRequestValue.new(file_id: "f", owner_tenant_id: tenant, kind: "stocks")

      expect(Imports::ImportPolicy.new(request, user:).apply(:start?)).to be(false)
    end
  end

  describe "状況" do
    # 時刻列と件数から優先順で導出する（data-model.md「取り込み（`imports`）」の表の 6 行）
    it "失敗・一部失敗・完了・反映中・置き場へ写し中・待機中を、優先順で導出する" do
      now = Time.current
      columns = {
        failed: { started_at: now, staged_at: now, finished_at: now, failed_rows: 1, failed_at: now, failure_reason: "not_permitted" },
        partially_failed: { started_at: now, staged_at: now, finished_at: now, failed_rows: 1 },
        succeeded: { started_at: now, staged_at: now, finished_at: now },
        applying: { started_at: now, staged_at: now },
        staging: { started_at: now },
        queued: {}
      }
      ids = tenancy { columns.transform_values { FactoryBot.create(:import, **_1).id } }

      expect(tenancy { ids.transform_values { described_class.find(actor, _1).status } }).to eq(columns.keys.index_with(&:itself))
    end
  end

  describe ".list・.find・.row_errors" do
    it "自社の取り込みだけを新しい順に返し、他社の取り込みの ID は nil になる" do
      theirs = tenancy(other) { FactoryBot.create(:import) }
      older, newer = tenancy { FactoryBot.create_list(:import, 2) }

      expect(tenancy { described_class.list(actor, first: 10, after: nil).values.map(&:id) }).to eq([ newer.id, older.id ])
      expect(tenancy { [ described_class.find(actor, theirs.id), described_class.find(actor, newer.id)&.id ] }).to eq([ nil, newer.id ])
    end

    it "失敗した行だけを行番号の順にページで返し、他社の取り込みの行は返さない" do
      import = tenancy { FactoryBot.create(:import) }
      tenancy do
        [ [ 5, "quantity: bad" ], [ 2, "item_code: bad" ], [ 3, nil ], [ 4, "item_code: duplicates row 2" ] ].each do |row_number, error|
          FactoryBot.create(:import_row, import:, row_number:, error:, applied_at: error ? nil : Time.current)
        end
      end
      theirs = tenancy(other) { FactoryBot.create(:import_row, error: "x").import_id }

      first = tenancy { described_class.row_errors(actor, import.id, first: 2, after: nil) }
      rest = tenancy { described_class.row_errors(actor, import.id, first: 2, after: first.cursors.last) }

      expect(first.values.map(&:row_number) + rest.values.map(&:row_number)).to eq([ 2, 4, 5 ])
      expect([ first.has_next_page, rest.has_next_page ]).to eq([ true, false ])
      expect(tenancy { described_class.row_errors(actor, theirs, first: 10, after: nil).values }).to be_empty
      expect { tenancy { described_class.row_errors(actor, import.id, first: 2, after: "x") } }.to raise_error(Page::InvalidCursor)
    end
  end

  describe ".reenqueue" do
    it "終わっていない取り込みにだけ新しいジョブを登録し、終えた取り込みと他社の取り込みには登録しない" do
      waiting, applying = tenancy { [ FactoryBot.create(:import), FactoryBot.create(:import, started_at: Time.current, staged_at: Time.current) ] }
      finished = tenancy { FactoryBot.create(:import, started_at: Time.current, staged_at: Time.current, finished_at: Time.current) }
      failed = tenancy { FactoryBot.create(:import, failed_at: Time.current, failure_reason: "header_mismatch") }
      theirs = tenancy(other) { FactoryBot.create(:import) }

      results = tenancy { [ waiting, applying, finished, failed, theirs ].map { described_class.reenqueue(_1.id) } }

      expect(results).to eq([ true, true, false, false, false ])
      expect(jobs.map { _1.arguments["arguments"] }).to match_array([ [ waiting.id, tenant ], [ applying.id, tenant ] ])
    end

    it "操作者でない値で読むと例外にする" do
      expect { tenancy { described_class.list(nil, first: 10, after: nil) } }.to raise_error(ArgumentError, /actor/)
    end

    it "テナントを開かずに呼ぶと例外にする" do
      expect { described_class.reenqueue(SecureRandom.uuid) }.to raise_error(Tenancy::MissingTenant)
    end
  end
end

# 取り込むファイルを置く（POST /imports/files の公開 API）。大きさの上限は、上限ちょうどと上限 + 1 を仕様の値で書く。定数から値を作ると、定数を誤って変えても通るからである
RSpec.describe Imports::Files, ".store" do
  let(:tenant) { FactoryBot.create(:tenant).id }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: tenant, name: "", email: "", role: "member", partner_code: "")
  end

  def store(content, filename: "stocks.csv") = Tenancy.with_tenant(tenant) { described_class.store(actor, filename:, content:) }
  def files = Tenancy.with_tenant(tenant) { Imports::ImportFile.pluck(:byte_size) }

  it "10 MB ちょうどのファイルは受け付け、大きさと名前を返す" do
    value = store("a" * 10_485_760, filename: "../dir/上限.csv").value

    expect([ value.filename, value.byte_size ]).to eq([ "上限.csv", 10_485_760 ])
    expect(files).to eq([ 10_485_760 ])
  end

  it "10 MB + 1 バイトのファイルは、ファイルを指す INVALID_INPUT で、置かない" do
    result = store("a" * 10_485_761)

    expect(result.failures.map { [ _1.code, _1.path ] }).to eq([ [ :invalid_input, [ :file ] ] ])
    expect(files).to be_empty
  end
end
