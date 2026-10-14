require "rails_helper"
require "rake"
require_relative "../support/scenarios"

# 一覧のために別のコンテキストへ写した値の一致（docs/adr/011 決定 2）。写しを保つ経路（品目の保存と取り込み、「出荷可能」の受け手）と、
# 元から作り直すタスク（bin/rails read_models:rebuild）が同じ写しを作ることを、シードと E2E の世界の作り方の全経路で確かめる。
# 写しを書く経路に抜けがあれば、作り直しがその分を足すか書き直し、数が 0 にならない
RSpec.describe "一覧のための写しの一致", type: :request do
  before(:context) { Rails.application.load_tasks unless Rake::Task.task_defined?("read_models:rebuild") }

  let!(:world) { DemoWorld.build(namespace: "copies#{SecureRandom.hex(3)}", variant: :e2e) }
  let(:supplier_id) { world.tenant_ids.fetch(:supplier) }
  let(:supplier_admin) { world.accounts.find { _1.persona == "supplier_admin" } }

  # 作り直しのタスクを流し、世界のテナントごとの [品目の写しを足した数, 書き直した数, 出荷依頼の受注番号を書き直した数] を返す。
  # テストの DB には、ほかの spec が残したテナントもあるので、世界のテナントの行だけを読む
  def rebuild
    output = StringIO.new
    $stdout = output
    Rake::Task["read_models:rebuild"].execute
    $stdout = STDOUT
    labels = output.string.scan(/テナント (\S+) の品目の写しを (\d+) 件足し、(\d+) 件書き直した/).to_h { [ _1, [ _2.to_i, _3.to_i ] ] }
    order_numbers = output.string.scan(/テナント (\S+) の出荷依頼の受注番号を (\d+) 件書き直した/).to_h { [ _1, _2.to_i ] }
    world.tenant_ids.to_h { |persona, tenant_id| [ persona, [ *labels.fetch(tenant_id), order_numbers.fetch(tenant_id) ] ] }
  ensure
    $stdout = STDOUT
  end

  def zeros = world.tenant_ids.transform_values { [ 0, 0, 0 ] }

  # 受注側の写しと品目を、コードと名前の組でコードの順に読む。どちらもパッケージの外に出さないモデルなので、SQL で読む
  def labels = rows_of("item_labels")

  def items = rows_of("items")

  def rows_of(table)
    Tenancy.with_tenant(supplier_id) do
      ActiveRecord::Base.lease_connection.select_rows(
        "SELECT code, name FROM #{table} WHERE owner_tenant_id = $1 ORDER BY code", "SQL", [ supplier_id ]
      )
    end
  end

  def login
    post "/session", params: { email: supplier_admin.email, password: supplier_admin.password }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  def import_items(rows)
    content = CSV.generate { |csv| [ Imports::CsvFormat::COLUMNS.fetch("items"), *rows ].each { csv << _1 } }
    post "/imports/files", params: { file: Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: "items.csv") },
      headers: { "Origin" => Rails.configuration.x.frontend_origin }
    import_id = mutate!("startImport", "import { id }", fileId: response.parsed_body.fetch("id"), kind: "ITEMS").dig("import", "id")
    DemoWorld::Jobs.drain(%w[Imports::RunJob])
    expect(query("query($id: ID!) { supplier { import(id: $id) { status } } }", id: import_id).dig("supplier", "import", "status"))
      .to eq("SUCCEEDED")
  end

  it "世界を作った後の作り直しは、何も足さず書き直さない。写しを消すか書き換えると、その数だけ足して書き直す" do
    expect(rebuild).to eq(zeros)

    # 対照：作り直しが何も比べていなくても 0 は返るので、食い違いを作ると 0 でない数を返し、写しを元に戻すことを確かめる
    removed, renamed = labels.first(2).map(&:first)
    Tenancy.with_tenant(supplier_id) do
      connection = ActiveRecord::Base.lease_connection
      connection.exec_delete("DELETE FROM item_labels WHERE code = $1", "SQL", [ removed ])
      connection.exec_update("UPDATE item_labels SET name = '食い違った名前' WHERE code = $1", "SQL", [ renamed ])
    end
    expect(rebuild).to eq(zeros.merge(supplier: [ 1, 1, 0 ]))
    expect(labels).to eq(items)
  end

  # 出荷依頼の受注番号は「出荷可能」の受け手が写す。受け手が写さなければ、世界の出荷依頼の数だけ書き直しが出る
  it "世界を作った後の作り直しは、出荷依頼の受注番号を書き直さない。写しを空にするか書き換えると、その数だけ書き直す" do
    expect(rebuild).to eq(zeros)

    # 対照：作り直しが何も比べていなくても 0 は返るので、食い違いを作ると 0 でない数を返し、写しを元に戻すことを確かめる
    blanked, renamed = order_number_rows.first(2).map(&:first)
    Tenancy.with_tenant(supplier_id) do
      connection = ActiveRecord::Base.lease_connection
      connection.exec_update("UPDATE shipment_requests SET sales_order_no = NULL WHERE sales_order_id = $1", "SQL", [ blanked ])
      connection.exec_update("UPDATE shipment_requests SET sales_order_no = 'SO-999999' WHERE sales_order_id = $1", "SQL", [ renamed ])
    end
    expect(rebuild).to eq(zeros.merge(supplier: [ 0, 0, 2 ]))
    expect(order_number_rows.map(&:last)).to eq(order_number_rows.map { _1[1] })
  end

  # 出荷依頼ごとの [受注 ID, 受注の受注番号, 写した受注番号]。受注と出荷はパッケージの外に出さないモデルなので、SQL で読む
  def order_number_rows
    Tenancy.with_tenant(supplier_id) do
      ActiveRecord::Base.lease_connection.select_rows(<<~SQL, "SQL", [ supplier_id ]).tap { expect(_1.size).to be >= 2 }
        SELECT r.sales_order_id, o.order_no, r.sales_order_no FROM shipment_requests r JOIN sales_orders o ON o.id = r.sales_order_id
        WHERE r.owner_tenant_id = $1 ORDER BY o.order_no
      SQL
    end
  end

  it "saveItem で品目の名前を変えた後も、作り直しは何も足さず書き直さない" do
    login
    item = query("{ supplier { items(first: 1, orderBy: { field: CODE, direction: ASC }) { nodes { code name unit unitPrice } } } }")
      .dig("supplier", "items", "nodes", 0)
    mutate!("saveItem", "item { id }", code: item["code"], name: "#{item["name"]} 改", unit: item["unit"], unitPrice: item["unitPrice"])
    expect(labels).to include([ item["code"], "#{item["name"]} 改" ])

    expect(rebuild).to eq(zeros)
  end

  it "品目の CSV の取り込みで品目の名前を変え、品目を足した後も、作り直しは何も足さず書き直さない" do
    login
    code = items.first.first
    import_items([ [ code, "取り込みで変えた名前", "個", 10, "true", nil, nil ], [ "NEW-CSV-1", "取り込みで足した品目", "個", 10, "false", 100, nil ] ])
    expect(labels).to include([ code, "取り込みで変えた名前" ], [ "NEW-CSV-1", "取り込みで足した品目" ])

    expect(rebuild).to eq(zeros)
  end
end
