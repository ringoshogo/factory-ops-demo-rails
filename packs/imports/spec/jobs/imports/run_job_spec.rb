require "rails_helper"

# 取り込みのジョブ（docs/adr/007 決定 5 の A-4、docs/architecture/data-model.md「取り込み（`imports`）」）。
# 置き場へ写す・反映する・締めるの 3 段階で、中断しても、継続の情報を失っても続きから進み、全行が 1 回ずつ反映される
RSpec.describe Imports::RunJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { FactoryBot.create(:tenant).id }
  let(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let(:actor) { Tenancy.with_tenant(tenant) { Partnerships::Authentication.acting_user(admin.id) } }
  let(:events) { [] }
  let(:collector) { Struct.new(:events) { def emit(event) = events << event }.new(events) }

  # 継続の情報を持たないまま実行を捨てる。Continuable が拾わない Exception にして、プロセスが落ちたときと同じく中断点を保存させない
  let(:crash) { stub_const("ImportJobCrash", Class.new(Exception)) }

  around do |example|
    Rails.event.subscribe(collector)
    example.run
  ensure
    Rails.event.unsubscribe(collector)
  end

  def tenancy(&) = Tenancy.with_tenant(tenant, &)

  def start(kind, csv)
    tenancy do
      file = Imports::Files.store(actor, filename: "#{kind}.csv", content: csv).value
      Imports::Runs.start(actor, Imports::Runs.request(actor, file_id: file.id, kind:)).value
    end
  end

  def items_csv(*rows) = [ "code,name,unit,tax_rate_percent,published,unit_price,price_effective_on", *rows ].join("\n") + "\n"
  def stocks_csv(*rows) = [ "item_code,quantity", *rows ].join("\n") + "\n"

  # 登録されたまま終わっていない、この取り込みのジョブ。中断で登録し直したジョブも含む
  def pending_jobs(import) = SolidQueue::Job.where(class_name: described_class.name, finished_at: nil).where("arguments LIKE ?", "%#{import.id}%").order(:id)

  # 登録されたジョブを古い順に 1 つ実行して、終わったことにする
  def run_next(import)
    job = pending_jobs(import).first
    ActiveJob::Base.execute(job.arguments)
    job.finished!
  end

  def run_all(import)
    run_next(import) while pending_jobs(import).exists?
  end

  # ジョブの実行中に、その継続が指定の段階とカーソルにいるか（activejob 8.1.4 の Continuation::TestHelper#during_step? と同じ読み方）
  def at?(step, cursor)
    job = ActiveSupport::ExecutionContext.to_h[:job]
    job.is_a?(described_class) && job.continuation.to_h["current"] == [ step.to_s, cursor ]
  end

  def stop_at(step, cursor)
    allow(described_class.queue_adapter).to receive(:stopping?) { at?(step, cursor) }
  end

  def crash_at(step, cursor)
    allow(described_class.queue_adapter).to receive(:stopping?) { at?(step, cursor) && raise(crash) }
  end

  def import_of(import) = tenancy { Imports::Runs.find(actor, import.id) }
  def staged_rows(import) = tenancy { Imports::ImportRow.where(import_id: import.id).count }
  def row_errors(import) = tenancy { Imports::Runs.row_errors(actor, import.id, first: 100, after: nil).values.map { [ _1.row_number, _1.message ] } }
  def movements = tenancy { Inventory::Stocks.movements(actor, first: 100, after: nil).values.map { [ _1.item_id, _1.type, _1.quantity ] } }
  # 品目コードの順の在庫数。在庫の行の無い品目は nil
  def on_hand(codes)
    tenancy do
      ids = Sales::Catalog.ids_by_codes(actor, codes).values_at(*codes)
      stocks = Inventory::Stocks.for_items(actor, ids)
      ids.map { stocks[_1]&.on_hand }
    end
  end
  def items = tenancy { Sales::Catalog.items(actor, first: 100, after: nil).values.to_h { [ _1.code, _1.unit_price ] } }

  describe "中断と再開" do
    before do
      stub_const("Imports::Staging::CHUNK_ROWS", 2)
      stub_const("Imports::Applying::CHUNK_ROWS", 2)
      tenancy { %w[A B C D E].each { FactoryBot.create(:item, code: _1) } }
    end

    let(:import) { start("stocks", stocks_csv("A,1", "B,2", "C,3", "D,4", "E,5")) }

    it "置き場へ写す途中と反映の途中で止めても、もう一度流すと続きから進み、全行が 1 回ずつ反映される" do
      stop_at(:stage, 3)
      run_next(import)

      expect([ staged_rows(import), import_of(import).status ]).to eq([ 2, :staging ])
      expect(pending_jobs(import).sole.arguments["continuation"]).to eq("completed" => [], "current" => [ "stage", 3 ])

      stop_at(:apply, 3)
      run_next(import)

      expect(import_of(import)).to have_attributes(status: :applying, total_rows: 5, applied_rows: 2, failed_rows: 0)
      expect(movements.size).to eq(2)

      allow(described_class.queue_adapter).to receive(:stopping?).and_return(false)
      run_all(import)

      expect(import_of(import)).to have_attributes(status: :succeeded, total_rows: 5, applied_rows: 5, failed_rows: 0)
      expect(on_hand(%w[A B C D E])).to eq([ 1, 2, 3, 4, 5 ])
      expect(movements.map { _1[1..] }.sort).to eq([ 1, 2, 3, 4, 5 ].map { [ "inbound", _1 ] })
    end

    it "置き場へ写す途中と反映の途中で実行を捨てても、再登録した新しいジョブが続きから進み、件数が行の数と合う" do
      crash_at(:stage, 3)
      expect { run_next(import) }.to raise_error(crash)
      pending_jobs(import).first.finished!
      expect(staged_rows(import)).to eq(2)

      expect(tenancy { Imports::Runs.reenqueue(import.id) }).to be(true)
      crash_at(:apply, 3)
      expect { run_next(import) }.to raise_error(crash)
      pending_jobs(import).first.finished!
      expect(import_of(import)).to have_attributes(applied_rows: 2, status: :applying)

      tenancy { Imports::Runs.reenqueue(import.id) }
      allow(described_class.queue_adapter).to receive(:stopping?).and_return(false)
      run_all(import)

      expect(import_of(import)).to have_attributes(status: :succeeded, total_rows: 5, applied_rows: 5, failed_rows: 0)
      expect(staged_rows(import)).to eq(5)
      expect(movements.size).to eq(5)
      expect(on_hand(%w[A B C D E])).to eq([ 1, 2, 3, 4, 5 ])
    end
  end

  describe "同じ取り込みの 2 つのジョブ" do
    # 後のジョブが置き場へ写す段階の始めを過ぎた後に、先のジョブが取り込みを終えてファイルの中身を消す順を、1 つの接続で作る
    it "置き場へ写し始めた後のジョブは、先のジョブが取り込みを終えていたら、例外にせずに何も書かずに終える" do
      tenancy { FactoryBot.create(:item, code: "A") }
      import = start("stocks", stocks_csv("A,2"))
      first_check = true
      allow(Imports::Chunk).to receive(:locked).and_wrap_original do |original, *args, &block|
        result = original.call(*args, &block)
        if first_check
          first_check = false
          described_class.new(import.id, tenant).perform_now
        end
        result
      end

      expect { Imports::Staging.run(import.id, tenant) { nil } }.not_to raise_error

      expect(import_of(import)).to have_attributes(status: :succeeded, total_rows: 1, applied_rows: 1)
      expect(staged_rows(import)).to eq(1)
      expect(movements.size).to eq(1)
    end
  end

  describe "件数の冪等" do
    it "成功 2 行・失敗 1 行のチャンクを反映した後、カーソルを保存する前に止まった実行をもう一度流しても、件数も品目も在庫も増えない" do
      tenancy { %w[A B].each { FactoryBot.create(:item, code: _1) } }
      import = start("stocks", stocks_csv("A,3", "NONE,1", "B,4"))
      original = pending_jobs(import).first.arguments

      crash_at(:apply, 4)
      expect { ActiveJob::Base.execute(original) }.to raise_error(crash)
      expect(import_of(import)).to have_attributes(applied_rows: 2, failed_rows: 1)

      allow(described_class.queue_adapter).to receive(:stopping?).and_return(false)
      ActiveJob::Base.execute(original)

      expect(import_of(import)).to have_attributes(status: :partially_failed, applied_rows: 2, failed_rows: 1)
      expect(movements.size).to eq(2)
      expect(on_hand(%w[A B])).to eq([ 3, 4 ])
      expect(row_errors(import)).to eq([ [ 3, "item_code: no item with this code" ] ])
      expect(items.keys).to match_array(%w[A B])
    end
  end

  describe "CSV の契約" do
    it "見出しが列名の順と一致しなければ、取り込み全体を失敗にし、置き場にも業務の表にも書かず、ファイルの中身を消す" do
      import = start("stocks", "quantity,item_code\n3,A\n")

      run_all(import)

      expect(import_of(import)).to have_attributes(status: :failed, applied_rows: 0, failed_rows: 0)
      expect(tenancy { Imports::Import.find(import.id).failure_reason }).to eq("header_mismatch")
      expect(staged_rows(import)).to eq(0)
      expect(tenancy { Imports::ImportFile.joins("JOIN imports ON imports.import_file_id = import_files.id").where(imports: { id: import.id }).pick(:content) }).to be_nil
    end

    it "新しい品目は有効期間 (,) の単価の行を持ち、同じコードの 2 行目と列の検証に外れた行は失敗にする" do
      import = start("items", items_csv("N-1,ボルト,個,10,true,120,", "N-1,ナット,個,10,true,130,", "N-2,座金,個,5,false,10,", "N-3,,個,8,false,10,"))

      run_all(import)

      expect(import_of(import)).to have_attributes(status: :partially_failed, applied_rows: 1, failed_rows: 3)
      expect(row_errors(import)).to eq([ [ 3, "code: duplicates row 2" ], [ 4, "tax_rate_percent: must be 8 or 10" ], [ 5, "name: can't be blank" ] ])
      expect(items).to eq("N-1" => 120)
      item_id = tenancy { Sales::Catalog.ids_by_codes(actor, %w[N-1]).fetch("N-1") }
      expect(tenancy { Sales::ItemPrices.history(actor, [ item_id ]).fetch(item_id).map { [ _1.valid_from, _1.valid_to, _1.unit_price ] } })
        .to eq([ [ nil, nil, 120 ] ])
    end

    it "既存の品目は、単価が改定日の単価と違うときだけ改定を予約し、空なら単価を変えない。改定日が空なら今日から" do
      tenancy do
        { "OLD-1" => 100, "OLD-2" => 200, "OLD-3" => 300, "OLD-4" => 400 }.each { |code, price| FactoryBot.create(:item, code:, unit_price: price) }
      end
      tomorrow = Date.current + 1
      import = start("items", items_csv("OLD-1,改名,個,10,false,100,", "OLD-2,改名,個,10,false,250,#{tomorrow.iso8601}",
        "OLD-3,改名,個,10,false,350,", "OLD-1x,新品,個,10,false,,", "OLD-4,改名,個,10,false,,"))

      run_all(import)

      expect(row_errors(import)).to eq([ [ 5, "unit_price: Unit price is required for a new item" ] ])
      ids = tenancy { Sales::Catalog.ids_by_codes(actor, %w[OLD-1 OLD-2 OLD-3 OLD-4]) }
      history = tenancy { Sales::ItemPrices.history(actor, ids.values) }.transform_values { |rows| rows.map { [ _1.valid_from, _1.unit_price ] } }
      expect(ids.transform_values { history.fetch(_1) }).to eq(
        "OLD-1" => [ [ nil, 100 ] ],
        "OLD-2" => [ [ nil, 200 ], [ tomorrow, 250 ] ],
        "OLD-3" => [ [ nil, 300 ], [ Date.current, 350 ] ],
        "OLD-4" => [ [ nil, 400 ] ]
      )
      expect(tenancy { Sales::Catalog.items_for(actor, ids.values).values.map(&:name) }).to all(eq("改名"))
    end

    # 段階を進めた後の例外は、Continuable が中断と同じく登録し直す（activejob 8.1.4 の resume_errors_after_advancing の既定は真）
    it "品目の列を書いた後に改定の予約が失敗したら、行の失敗にせずチャンクごと戻し、登録し直したジョブが反映し直す" do
      tenancy { FactoryBot.create(:item, code: "OLD-1", name: "旧名", unit_price: 100) }
      import = start("items", items_csv("OLD-1,改名,個,10,false,150,", "NEW-1,新品,個,10,false,10,"))
      allow(Sales::ItemPrices).to receive(:schedule).and_return(OperationResult.failure(:invalid_input, path: [ :effective_on ], message: "x"))

      run_next(import)

      expect(import_of(import)).to have_attributes(status: :applying, applied_rows: 0, failed_rows: 0)
      expect(tenancy { Sales::Catalog.items(actor, first: 10, after: nil).values.map { [ _1.name, _1.unit_price ] } }).to eq([ [ "旧名", 100 ] ])
      expect(pending_jobs(import).sole.arguments["continuation"]).to eq("completed" => [ "stage" ], "current" => [ "apply", nil ])

      allow(Sales::ItemPrices).to receive(:schedule).and_call_original
      run_all(import)

      expect(import_of(import)).to have_attributes(status: :succeeded, applied_rows: 2)
      expect(items).to eq("OLD-1" => 150, "NEW-1" => 10)
    end

    # 改定日の今日は、単価の改定の予約と同じく日本時間で決まる（docs/adr/006 決定 6、docs/architecture/context-map.md「検収と請求の流れ」）
    it "日本時間の 0〜9 時の取り込みは、空の改定日を日本時間の今日にし、その前日の改定日を失敗にする" do
      now = Time.utc(2026, 10, 11, 16, 0)

      travel_to(now - 1.minute) { tenancy { %w[OLD-1 OLD-2].each { FactoryBot.create(:item, code: _1, unit_price: 100) } } }
      travel_to(now) do
        import = start("items", items_csv("OLD-1,改名,個,10,false,150,", "OLD-2,改名,個,10,false,150,2026-10-11"))
        run_all(import)
        expect(row_errors(import)).to eq([ [ 3, "price_effective_on: must be today or later" ] ])
      end

      # 対照：この時刻の UTC の日付は前日である
      expect(now.utc.to_date).to eq(Date.new(2026, 10, 11))
      id = tenancy { Sales::Catalog.ids_by_codes(actor, %w[OLD-1]).fetch("OLD-1") }
      expect(tenancy { Sales::ItemPrices.history(actor, [ id ]).fetch(id).map { [ _1.valid_from, _1.unit_price ] } })
        .to eq([ [ nil, 100 ], [ Date.new(2026, 10, 12), 150 ] ])
    end

    it "単価の改定日が今日より前の行と、日付の形でない行は失敗にする" do
      tenancy { FactoryBot.create(:item, code: "OLD-1", unit_price: 100) }
      import = start("items", items_csv("OLD-1,改名,個,10,false,150,#{(Date.current - 1).iso8601}", "OLD-1x,新品,個,10,false,10,2026/10/12"))

      run_all(import)

      expect(row_errors(import)).to eq([ [ 2, "price_effective_on: must be today or later" ], [ 3, "price_effective_on: must be a date in YYYY-MM-DD" ] ])
      expect(items).to eq("OLD-1" => 100)
    end

    it "在庫は目標の在庫数で、引当済みの数量より少なくする行と、同じ品目コードの 2 行目を失敗にする" do
      tenancy do
        %w[A B].each { FactoryBot.create(:item, code: _1) }
        a = Sales::Catalog.ids_by_codes(actor, %w[A]).fetch("A")
        Inventory::Adjustment.set_quantity(actor, item_id: a, quantity: 5, reason: "棚卸")
        Inventory::Allocation.allocate(actor, [ { sales_order_line_id: SecureRandom.uuid, item_id: a, quantity: 4 } ])
      end
      import = start("stocks", stocks_csv("A,3", "B,7", "B,8", "B,-1", "B", " ,3"))

      run_all(import)

      expect(row_errors(import).map { [ _1[0], _1[1].split(":").first ] })
        .to eq([ [ 2, "quantity" ], [ 4, "item_code" ], [ 5, "quantity" ], [ 6, "row has 1 columns, expected 2" ], [ 7, "item_code" ] ])
      expect(on_hand(%w[A B])).to eq([ 5, 7 ])
    end

    # 上限は列の型（数量は integer、単価は bigint）の最大値。上限ちょうどと上限 + 1 を仕様の値で書く。定数から値を作ると、定数を誤って変えても通るからである
    it "数量は 2147483647 まで、単価は 9223372036854775807 までを反映し、1 大きい値の行を失敗にする" do
      tenancy { %w[A B].each { FactoryBot.create(:item, code: _1) } }
      stocks = start("stocks", stocks_csv("A,2147483647", "B,2147483648"))
      prices = start("items", items_csv("MAX-1,上限,個,10,false,9223372036854775807,", "MAX-2,上限超え,個,10,false,9223372036854775808,"))

      [ stocks, prices ].each { run_all(_1) }

      expect(on_hand(%w[A])).to eq([ 2_147_483_647 ])
      expect(row_errors(stocks)).to eq([ [ 3, "quantity: must be an integer between 0 and 2147483647" ] ])
      expect(items.slice("MAX-1", "MAX-2")).to eq("MAX-1" => 9_223_372_036_854_775_807)
      expect(row_errors(prices)).to eq([ [ 3, "unit_price: must be an integer between 0 and 9223372036854775807" ] ])
    end

    it "見出しだけのファイルは、0 行の取り込みとして完了する" do
      import = start("stocks", stocks_csv)

      run_all(import)

      expect(import_of(import)).to have_attributes(status: :succeeded, total_rows: 0, applied_rows: 0, failed_rows: 0)
    end

    it "見出しを除いて 50,000 行までを受け付け、超えたファイルは取り込み全体を失敗にする" do
      expect(Imports::Staging::MAX_ROWS).to eq(50_000)
      stub_const("Imports::Staging::MAX_ROWS", 2)
      tenancy { %w[A B C].each { FactoryBot.create(:item, code: _1) } }
      within = start("stocks", stocks_csv("A,1", "B,1"))
      over = start("stocks", stocks_csv("A,1", "B,1", "C,1"))

      run_all(within)
      run_all(over)

      expect(import_of(within)).to have_attributes(status: :succeeded, applied_rows: 2)
      expect(import_of(over)).to have_attributes(status: :failed, applied_rows: 0)
      expect(tenancy { Imports::Import.find(over.id).failure_reason }).to eq("too_many_rows")
    end

    it "UTF-8 でないファイルと、CSV として壊れたファイルは、取り込み全体を失敗にする。BOM は読み飛ばす" do
      tenancy { FactoryBot.create(:item, code: "A") }
      broken = { "invalid_encoding" => "item_code,quantity\n\xff,1\n".b, "malformed_csv" => "item_code,quantity\n\"A,1\n" }
      imports = broken.transform_values { start("stocks", _1) }
      with_bom = start("stocks", "﻿#{stocks_csv('A,2')}")

      [ *imports.values, with_bom ].each { run_all(_1) }

      expect(imports.transform_values { |import| tenancy { Imports::Import.find(import.id).failure_reason } }).to eq(broken.keys.index_with(&:itself))
      expect(import_of(with_bom)).to have_attributes(status: :succeeded, applied_rows: 1)
    end
  end

  describe "部分失敗" do
    it "3 行のうち 1 行が不正なファイルは、反映が 2 行・失敗が 1 行・状況が一部失敗になり、終わりと件数をログに出す" do
      tenancy { %w[A B C].each { FactoryBot.create(:item, code: _1) } }
      import = start("stocks", stocks_csv("A,1", "B,x", "C,3"))

      run_all(import)

      expect(import_of(import)).to have_attributes(status: :partially_failed, total_rows: 3, applied_rows: 2, failed_rows: 1)
      expect(import_of(import).finished_at).to be_present
      expect(row_errors(import)).to eq([ [ 3, "quantity: must be an integer between 0 and 2147483647" ] ])
      expect(events.select { _1[:name].start_with?("imports.") }.map { [ _1[:name], _1[:payload].except(:duration_ms) ] }).to eq([
        [ "imports.chunk_applied", { kind: "stocks", import_id: import.id, applied_rows: 2, failed_rows: 1 } ],
        [ "imports.finished", { kind: "stocks", import_id: import.id, result: "partially_failed", total_rows: 3, applied_rows: 2, failed_rows: 1 } ]
      ])
    end
  end

  describe "取り込みを始めたユーザーの役割" do
    it "品目の取り込みは、反映の前に admin でなくなったら、何も反映せずに取り込み全体を失敗にする" do
      import = start("items", items_csv("N-1,ボルト,個,10,false,120,"))
      tenancy { admin.update!(role: "member") }

      run_all(import)

      expect(import_of(import)).to have_attributes(status: :failed, applied_rows: 0)
      expect(tenancy { Imports::Import.find(import.id).failure_reason }).to eq("not_permitted")
      expect(items).to be_empty
    end

    it "反映の途中で admin でなくなったら、次のチャンクで取り込み全体を失敗にし、反映したチャンクは残して残りを書かない" do
      stub_const("Imports::Applying::CHUNK_ROWS", 1)
      import = start("items", items_csv("N-1,ボルト,個,10,false,120,", "N-2,ナット,個,10,false,30,"))
      stop_at(:apply, 2)
      run_next(import)
      expect(import_of(import)).to have_attributes(status: :applying, applied_rows: 1)

      tenancy { admin.update!(role: "member") }
      allow(described_class.queue_adapter).to receive(:stopping?).and_return(false)
      run_all(import)

      expect(import_of(import)).to have_attributes(status: :failed, applied_rows: 1, failed_rows: 0)
      expect(tenancy { Imports::Import.find(import.id).failure_reason }).to eq("not_permitted")
      expect(items).to eq("N-1" => 120)
    end

    it "在庫の取り込みは、member の名義でも反映する" do
      tenancy { FactoryBot.create(:item, code: "A") }
      import = start("stocks", stocks_csv("A,2"))
      tenancy { admin.update!(role: "member") }

      run_all(import)

      expect(import_of(import)).to have_attributes(status: :succeeded, applied_rows: 1)
    end
  end

  it "テナントごとに 1 つずつ、imports のキューで動き、チャンクごとにテナントのトランザクションを開く" do
    job = described_class.new("import-id", tenant)

    expect([ job.queue_name, job.concurrency_key, described_class.concurrency_limit, described_class.concurrency_duration ])
      .to eq([ "imports", "Imports::RunJob/#{tenant}", 1, 1.hour ])
    expect(described_class.tenant_transaction_unit).to eq(:per_chunk)
  end
end
