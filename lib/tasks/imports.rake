# 取り込みの運用のタスク（docs/adr/007 決定 5 の A-4）
namespace :imports do
  # プロセスが強制終了したジョブを、Solid Queue は ProcessPrunedError で失敗にし、自動では再試行しない
  # （solid_queue 1.7.0 の README「Jobs interrupted by non-graceful process death」）。運用者は、取り込みのジョブの失敗を見てから、
  # 失敗したジョブの引数にある取り込み ID とテナント ID を渡して流す。テナントを明示して開く（decisions.md 2 章）
  desc "終わっていない取り込み（IMPORT_ID）に、テナント（TENANT_ID）の名義で新しいジョブを登録する"
  task reenqueue: :environment do
    import_id, tenant_id = %w[IMPORT_ID TENANT_ID].map do |name|
      ENV.fetch(name) { abort "imports:reenqueue: IMPORT_ID と TENANT_ID に、失敗した取り込みのジョブの引数の値を渡す" }
    end
    enqueued = Tenancy.with_tenant(tenant_id) { Imports::Runs.reenqueue(import_id) }
    abort "imports:reenqueue: 取り込み #{import_id} は終えたか、テナント #{tenant_id} に無い" unless enqueued

    puts "imports:reenqueue: 取り込み #{import_id} のジョブを登録した"
  end

  # 手で確かめる取り込みの CSV（品目）を作る。コードは実行ごとに変え、同じテナントに何度取り込んでも新しい品目になる
  desc "品目の CSV を ROWS 行（既定 50,000）作り、tmp/imports/ に書く"
  task :sample, [ :rows ] => :environment do |_task, args|
    rows = Integer(args[:rows] || 50_000)
    prefix = "S#{Time.current.strftime('%Y%m%d%H%M%S')}"
    path = Rails.root.join("tmp/imports/items-#{prefix}-#{rows}.csv")
    FileUtils.mkdir_p(path.dirname)
    CSV.open(path, "w") do |csv|
      csv << Imports::CsvFormat::COLUMNS.fetch("items")
      rows.times { |index| csv << [ format("%s-%06d", prefix, index + 1), "試験の品目 #{index + 1}", "個", 10, false, 100 + index % 900, nil ] }
    end
    puts "imports:sample: #{path}（#{rows} 行、#{File.size(path)} バイト）"
  end
end
