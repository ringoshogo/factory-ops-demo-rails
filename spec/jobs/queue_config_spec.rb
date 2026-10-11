require "rails_helper"

# キューとワーカーを型ごとに分ける（docs/adr/007 決定 7）。どのジョブも、ワーカーのあるキューに載り、
# 定期のジョブは実在するジョブのクラスを指す
RSpec.describe "キューとワーカーの設定" do
  def load_yaml(name, env)
    YAML.safe_load(ERB.new(Rails.root.join("config/#{name}.yml").read).result, aliases: true).fetch(env)
  end

  let(:workers) { load_yaml("queue", "production").fetch("workers") }
  # 送信のジョブはパッケージの外から参照できないので、名前で引く
  let(:mail_jobs) { %w[Notifications::CriticalDeliveryJob Notifications::BestEffortMailJob].map(&:constantize) }

  it "events・external_mail・imports・default のワーカーを、決めたスレッド数で置く" do
    expect(workers.to_h { [ _1.fetch("queues"), _1.fetch("threads") ] })
      .to eq("events" => 3, "external_mail" => 2, "imports" => 1, "default" => 2)
  end

  it "どのジョブも、ワーカーのあるキューに載る" do
    Rails.application.eager_load!
    jobs = ApplicationJob.descendants.select { _1.name&.safe_constantize == _1 }

    expect(jobs.to_h { [ _1.name, _1.new.queue_name ] }.reject { |_name, queue| workers.map { _1["queues"] }.include?(queue) }).to eq({})
    expect(Contracts::EventJob.queue_name).to eq("events")
    expect(mail_jobs.map(&:queue_name)).to all(eq("external_mail"))
  end

  it "送信の 2 つのジョブは、SendGrid への同時の送信の上限を合わせて 2 つで共有する" do
    expect(mail_jobs.map { [ _1.concurrency_limit, _1.new("x", {}).concurrency_key ] }).to all(eq([ 2, "sendgrid/sendgrid" ]))
  end

  it "定期のジョブは、Webhook の受信を毎分拾い、毎日消す。開発と本番で同じものを流す" do
    %w[development production].each do |env|
      tasks = load_yaml("recurring", env)

      expect(tasks.slice("process_webhook_inbox", "purge_webhook_inbox").transform_values { _1.values_at("class", "schedule") })
        .to eq("process_webhook_inbox" => [ "Notifications::ProcessInboxJob", "every minute" ],
          "purge_webhook_inbox" => [ "Notifications::PurgeInboxJob", "every day at 4am" ])
      expect(tasks.values.filter_map { _1["class"] }.map(&:safe_constantize)).to all(be < ApplicationJob)
    end
  end
end
