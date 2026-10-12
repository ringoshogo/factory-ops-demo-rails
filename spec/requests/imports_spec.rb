require "rails_helper"

# 取り込みの入口（docs/adr/007 決定 5 の A-4、docs/architecture/graphql-schema.md「役割による制限」）。ファイルの受け口は
# セッションで認証し、Origin を許可した origin と比べて CSRF を防ぐ。startImport は種類で役割が変わり、監査の行を残す。
# 業務の分岐は packs/imports/spec の単体が確かめ、ここは入口の配線と、進み具合が GraphQL で読めることを見る
RSpec.describe "取り込み", type: :request do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  let(:admin) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user, :admin) } }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:origin) { Rails.configuration.x.frontend_origin }

  def upload(content, headers: { "Origin" => origin }, filename: "items.csv")
    post "/imports/files", params: { file: Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: filename) },
      headers:
  end

  def files = Tenancy.with_tenant(supplier.id) { ApplicationRecord.connection.select_values("SELECT byte_size FROM import_files") }

  def start_import(file_id, kind)
    graphql_body(<<~GRAPHQL, input: { fileId: file_id, kind: })
      mutation($input: StartImportInput!) { startImport(input: $input) { import { id kind status } errors { code path } } }
    GRAPHQL
  end

  def run_import_jobs
    SolidQueue::Job.where(class_name: "Imports::RunJob", finished_at: nil).order(:id).each do |job|
      ActiveJob::Base.execute(job.arguments)
      job.finished!
    end
  end

  describe "POST /imports/files" do
    before { login_as(admin) }

    it "許可した origin からの CSV を置き、ID と名前と大きさを返す。業務の表には何も起きない" do
      upload("item_code,quantity\n")

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include("filename" => "items.csv", "byteSize" => 19)
      expect(files).to eq([ 19 ])
      expect(Tenancy.with_tenant(supplier.id) { ApplicationRecord.connection.select_value("SELECT count(*) FROM imports") }).to eq(0)
    end

    # 上限は仕様の値で書く（IB-25）
    it "10 MB ちょうどのファイルを受け付け、10 MB + 1 バイトのファイルを 413 で拒んで置かない" do
      upload("a" * 10_485_760)
      expect(response).to have_http_status(:created)

      upload("a" * 10_485_761)
      expect(response).to have_http_status(:content_too_large)
      expect(files).to eq([ 10_485_760 ])
    end

    it "Origin が許可した origin と違うか無い要求は 403 で拒み、置かない" do
      upload("item_code,quantity\n", headers: { "Origin" => "https://evil.example" })
      expect(response).to have_http_status(:forbidden)
      upload("item_code,quantity\n", headers: {})
      expect(response).to have_http_status(:forbidden)

      expect(files).to be_empty
      # 対照：同じセッションでも、許可した origin からなら置ける
      upload("item_code,quantity\n")
      expect(files.size).to eq(1)
    end

    it "ファイルの無い要求は 400" do
      post "/imports/files", params: { file: "not a file" }, headers: { "Origin" => origin }

      expect(response).to have_http_status(:bad_request)
    end
  end

  it "ログインしていない要求と、世代の古いセッションの要求は 401" do
    upload("item_code,quantity\n")
    expect(response).to have_http_status(:unauthorized)

    login_as(admin)
    Tenancy.with_tenant(supplier.id) { admin.update!(session_version: admin.session_version + 1) }
    upload("item_code,quantity\n")
    expect(response).to have_http_status(:unauthorized)
    expect(files).to be_empty
  end

  describe "startImport" do
    it "admin が品目の取り込みを始めると、取り込みとジョブができ、取り込みを対象にした監査の行が相手を空にして残る" do
      login_as(admin)
      upload("code,name,unit,tax_rate_percent,published,unit_price,price_effective_on\nN-1,ボルト,個,10,false,120,\n")

      started = start_import(response.parsed_body.fetch("id"), "ITEMS").dig("data", "startImport")

      expect(started).to include("errors" => [], "import" => include("kind" => "ITEMS", "status" => "QUEUED"))
      import_id = started.dig("import", "id")
      audit = Tenancy.with_tenant(supplier.id) { AuditLog.where(action: "import.start").sole }
      expect(audit.attributes.slice("actor_user_id", "target_type", "target_id", "counterparty_tenant_id"))
        .to eq("actor_user_id" => admin.id, "target_type" => "Import", "target_id" => import_id, "counterparty_tenant_id" => nil)
      expect(SolidQueue::Job.where(class_name: "Imports::RunJob").sole.arguments["arguments"]).to eq([ import_id, supplier.id ])
    end

    it "member は在庫の取り込みを始められ、品目の取り込みは FORBIDDEN で何も書かない" do
      login_as(member)
      upload("item_code,quantity\n")
      file_id = response.parsed_body.fetch("id")

      forbidden = start_import(file_id, "ITEMS")
      expect(forbidden.fetch("errors").map { _1.dig("extensions", "code") }).to eq([ "FORBIDDEN" ])
      expect(Tenancy.with_tenant(supplier.id) { ApplicationRecord.connection.select_value("SELECT count(*) FROM imports") }).to eq(0)

      expect(start_import(file_id, "STOCKS").dig("data", "startImport", "import", "kind")).to eq("STOCKS")
    end

    it "他社のファイルは NOT_FOUND、同じファイルの 2 回目は CONFLICT" do
      theirs = Tenancy.with_tenant(other.id) { FactoryBot.create(:import_file).id }
      login_as(admin)
      upload("item_code,quantity\n")
      file_id = response.parsed_body.fetch("id")

      expect(start_import(theirs, "STOCKS").dig("data", "startImport", "errors")).to eq([ { "code" => "NOT_FOUND", "path" => nil } ])
      expect(start_import(file_id, "STOCKS").dig("data", "startImport", "errors")).to eq([])
      expect(start_import(file_id, "STOCKS").dig("data", "startImport", "errors")).to eq([ { "code" => "CONFLICT", "path" => [ "fileId" ] } ])
    end
  end

  it "取り込みの進み具合と失敗した行を、supplier.imports・supplier.import・Import.rowErrors で読む" do
    Tenancy.with_tenant(supplier.id) { FactoryBot.create(:item, code: "A") }
    login_as(member)
    upload("item_code,quantity\nA,4\nB,1\n")
    import_id = start_import(response.parsed_body.fetch("id"), "STOCKS").dig("data", "startImport", "import", "id")

    run_import_jobs

    imports = query("{ supplier { imports { nodes { id status totalRows appliedRows failedRows } } } }").dig("supplier", "imports", "nodes")
    expect(imports).to eq([ { "id" => import_id, "status" => "PARTIALLY_FAILED", "totalRows" => 3 - 1, "appliedRows" => 1, "failedRows" => 1 } ])
    detail = query("query($id: ID!) { supplier { import(id: $id) { finishedAt rowErrors { nodes { rowNumber message } } } } }", id: import_id)
    expect(detail.dig("supplier", "import", "finishedAt")).to be_present
    expect(detail.dig("supplier", "import", "rowErrors", "nodes")).to eq([ { "rowNumber" => 3, "message" => "item_code: no item with this code" } ])
  end
end
