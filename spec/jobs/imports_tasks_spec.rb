require "rails_helper"
require "rake"

# 取り込みの運用のタスク（docs/adr/007 決定 5 の A-4）。再登録は、渡したテナントで終わっていない取り込みにだけジョブを登録する
RSpec.describe "imports の rake タスク" do
  before(:context) { Rails.application.load_tasks unless Rake::Task.task_defined?("imports:reenqueue") }

  let(:tenant) { FactoryBot.create(:tenant).id }

  def with_env(values)
    previous = values.keys.to_h { [ _1, ENV[_1] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def reenqueue(import_id, tenant_id = tenant)
    with_env("IMPORT_ID" => import_id, "TENANT_ID" => tenant_id) { Rake::Task["imports:reenqueue"].execute }
  end

  def jobs = SolidQueue::Job.where(class_name: "Imports::RunJob").where("arguments LIKE ?", "%#{tenant}%")

  it "imports:reenqueue は、終わっていない取り込みに、取り込み ID とテナント ID を引数にしたジョブを登録する" do
    import = Tenancy.with_tenant(tenant) { FactoryBot.create(:import, started_at: Time.current) }

    expect { reenqueue(import.id) }.to output(/#{import.id} のジョブを登録した/).to_stdout

    expect(jobs.sole.arguments["arguments"]).to eq([ import.id, tenant ])
  end

  it "imports:reenqueue は、終えた取り込みと、別のテナントを渡した取り込みには登録せずに止まる" do
    finished = Tenancy.with_tenant(tenant) { FactoryBot.create(:import, finished_at: Time.current) }
    waiting = Tenancy.with_tenant(tenant) { FactoryBot.create(:import) }

    expect { reenqueue(finished.id) }.to raise_error(SystemExit).and output(/終えたか/).to_stderr
    expect { reenqueue(waiting.id, FactoryBot.create(:tenant).id) }.to raise_error(SystemExit).and output(/無い/).to_stderr
    expect(jobs).to be_empty
  end

  it "imports:reenqueue は、取り込み ID かテナント ID が無ければ止まる" do
    with_env("IMPORT_ID" => nil, "TENANT_ID" => nil) do
      expect { Rake::Task["imports:reenqueue"].execute }.to raise_error(SystemExit).and output(/IMPORT_ID と TENANT_ID/).to_stderr
    end
  end

  it "imports:sample は、見出しと指定の行数の品目の CSV を tmp/imports/ に書く" do
    existing = Dir[Rails.root.join("tmp/imports/*-3.csv")]
    expect { Rake::Task["imports:sample"].execute(Rake::TaskArguments.new([ :rows ], [ "3" ])) }.to output(/（3 行/).to_stdout
    path = (Dir[Rails.root.join("tmp/imports/*-3.csv")] - existing).sole
    rows = CSV.read(path)

    expect(rows.first).to eq(%w[code name unit tax_rate_percent published unit_price price_effective_on])
    expect(rows.size).to eq(4)
  ensure
    File.delete(path) if path
  end
end
