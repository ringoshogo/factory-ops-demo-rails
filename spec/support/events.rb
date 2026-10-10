# テストでのイベントの流し方（docs/adr/005）。Active Job の :test アダプタに差し替えず、
# Contracts.publish が solid_queue_jobs に書いた行を読んで、受け手まで流す。
module EventHelpers
  # 登録済みのイベントのジョブを古い順に実行する。受け手が出した次のイベントも、無くなるまで流す。
  # times: 2 で、同じジョブを 2 回実行する（at-least-once の重複配送）。
  # newest_first: true で、新しいジョブから実行する（イベントの届く順の入れ替わり）。
  # Tenancy.with_tenant の外で呼ぶ。受け手は宛先テナントで Tenancy.with_tenant を開くので、中で呼ぶと入れ子になる。
  # 受け手の中の N+1 は、HTTP の要求を流す example でも検出する（spec/support/bullet.rb）
  def deliver_enqueued_events(times: 1, newest_first: false)
    raise "deliver_enqueued_events は Tenancy.with_tenant の外で呼ぶ" if Current.tenant_id.present?

    BulletDetection.wrap do
      while (job = newest_first ? enqueued_event_jobs.last : enqueued_event_jobs.first)
        times.times { ActiveJob::Base.execute(job.arguments) }
        job.finished!
      end
    end
  end

  def enqueued_event_jobs
    SolidQueue::Job.where(class_name: "Contracts::EventJob", finished_at: nil).order(:id)
  end
end

RSpec.configure do |config|
  config.include EventHelpers
end
