class DemoWorld
  # 登録済みのジョブを、ワーカーを待たずにその場で流す。シードと E2E の世界の準備と、テストのイベントの配送
  # （spec/support/events.rb）がこの 1 つの流し方を使う（docs/adr/005 決定 6）。
  # solid_queue_jobs の行を読んで ActiveJob::Base.execute で動かし、実行の後の後始末を Solid Queue のワーカーと同じ順で行う
  # （solid_queue 1.7.0 の app/models/solid_queue/claimed_execution.rb の finished・finalize）。テストと違ってシードは巻き戻らないので、
  # finished! だけでは実行待ちの行と同時実行の制御のセマフォが残り、bin/jobs が同じジョブをもう一度動かし、
  # 同じテナントの次の取り込みが Imports::RunJob の limits_concurrency の duration まで待たされる
  module Jobs
    # その場で流すジョブ。イベントと取り込みだけで、通知のジョブ（外部への送信）は流さずに bin/jobs に任せる
    CLASS_NAMES = %w[Contracts::EventJob Imports::RunJob].freeze

    # class_names の実行待ちのジョブを古い順に実行し、実行したジョブが登録したジョブも、無くなるまで流す。
    # times: 2 で同じジョブを 2 回実行し（at-least-once の重複配送）、newest_first: true で新しいジョブから実行する（届く順の入れ替わり）。
    # Tenancy.with_tenant の外で呼ぶ。ジョブは宛先テナントで Tenancy.with_tenant を開くので、中で呼ぶと入れ子になる
    def self.drain(class_names = CLASS_NAMES, times: 1, newest_first: false)
      raise ArgumentError, "DemoWorld::Jobs.drain は Tenancy.with_tenant の外で呼ぶ" if Current.tenant_id.present?

      while (job = newest_first ? ready(class_names).last : ready(class_names).first)
        execute(job, times:)
      end
    end

    # 実行待ち（ready）のジョブ。同時実行の上限で待つ（blocked）ジョブと、時刻を待つ（scheduled）ジョブは、
    # ワーカーと同じく実行待ちになるまで動かさない
    def self.ready(class_names)
      SolidQueue::Job.where(class_name: class_names, finished_at: nil).where(id: SolidQueue::ReadyExecution.select(:job_id)).order(:id)
    end

    # 終わっていないジョブ。drain の後に残っていれば、上限か時刻を待つジョブである
    def self.unfinished(class_names = CLASS_NAMES)
      SolidQueue::Job.where(class_name: class_names, finished_at: nil).order(:id)
    end

    # ジョブを実行し、1 つのトランザクションで実行待ちの行を消して終わったことにしてから、同時実行の制御のセマフォを返し、
    # 上限で待っていた同じ鍵の次のジョブを実行待ちにする。セマフォを返すのはトランザクションの外で、返す処理の失敗が
    # 終えたジョブを戻さないようにする（ワーカーの finalize と同じ）
    def self.execute(job, times: 1)
      times.times { ActiveJob::Base.execute(job.arguments) }
      SolidQueue::Job.transaction do
        SolidQueue::ReadyExecution.where(job_id: job.id).delete_all
        job.finished!
      end
      job.unblock_next_blocked_job
    end
  end
end
