require "rails_helper"
require "rake"

# 再送の rake タスク（docs/adr/007 決定 2）。テナントを 1 つずつ回り、失敗した確実な送信を同じ送信記録のまま登録し直す
RSpec.describe "notifications:redeliver" do
  before(:context) { Rails.application.load_tasks unless Rake::Task.task_defined?("notifications:redeliver") }

  let(:task) { Rake::Task["notifications:redeliver"] }
  let(:at) { Time.zone.parse("2026-10-12 10:00") }

  def run(since)
    previous = ENV["SINCE"]
    ENV["SINCE"] = since
    expect { task.execute }.to output(/合わせて/).to_stdout
  ensure
    ENV["SINCE"] = previous
  end

  it "どのテナントの失敗した送信記録も、新しい送信記録を作らずに登録し直す" do
    tenants = FactoryBot.create_list(:tenant, 2).map(&:id)
    deliveries = tenants.map do |tenant|
      Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, failed_at: at, failure_reason: "http_401") }
    end

    run((at - 1.hour).iso8601)

    jobs = SolidQueue::Job.where(class_name: "Notifications::CriticalDeliveryJob", finished_at: nil)
      .where(tenants.map { "arguments LIKE ?" }.join(" OR "), *tenants.map { "%#{_1}%" })
    expect(jobs.map { _1.arguments.dig("arguments", 0) }).to match_array(deliveries.map(&:id))
    expect(jobs.map { _1.arguments["tenant_id"] }).to match_array(tenants)
    tenants.zip(deliveries).each do |tenant, delivery|
      # 送信記録のモデルはパッケージの外から参照できないので、表を読む
      expect(Tenancy.with_tenant(tenant) { ApplicationRecord.connection.select_rows("SELECT id, failed_at FROM email_deliveries") })
        .to eq([ [ delivery.id, nil ] ])
    end
  end

  it "SINCE が無ければ止まる" do
    previous = ENV.delete("SINCE")
    expect { task.execute }.to raise_error(SystemExit).and output(/SINCE/).to_stderr
  ensure
    ENV["SINCE"] = previous
  end
end
