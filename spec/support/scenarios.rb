require_relative "events"
require_relative "request_helpers"

# 重要シナリオの補助（docs/guides/testing.md「重要シナリオ」）。シナリオは 2 社のユーザーとしてログインし（login_as）、
# GraphQL の入口を通して操作する（query）。イベントは deliver_enqueued_events で受け手まで流す
module ScenarioHelpers
  include RequestHelpers

  # mutation を呼び、payload を返す。selection は payload の中で選ぶ項目
  def mutate(name, selection = "errors { code }", **input)
    query(<<~GRAPHQL, input:).fetch(name)
      mutation($input: #{name[0].upcase}#{name[1..]}Input!) { #{name}(input: $input) { #{selection} } }
    GRAPHQL
  end

  # mutation が成功したことを確かめ、payload を返す
  def mutate!(name, selection, **input)
    mutate(name, "#{selection} errors { code path }", **input).tap { |payload| expect(payload["errors"]).to eq([]) }
  end

  # 登録済みのイベントのうち、最も古い 1 件だけを受け手まで流す
  def deliver_oldest_event(times: 1)
    job = enqueued_event_jobs.first
    BulletDetection.wrap { times.times { ActiveJob::Base.execute(job.arguments) } }
    job.finished!
  end

  # 登録済みのイベントのうち、event_name のペイロードを古い順に返す
  def enqueued_payloads(event_name)
    enqueued_event_jobs.map { _1.arguments.fetch("arguments") }.select { _1.first == event_name }.map(&:second)
  end
end

RSpec.configure do |config|
  config.include ScenarioHelpers, :scenario
end
