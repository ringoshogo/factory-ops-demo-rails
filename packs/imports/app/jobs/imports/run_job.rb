module Imports
  # 取り込みのジョブ（docs/adr/007 決定 5 の A-4）。置き場へ写す・反映する・締めるの 3 段階で、チャンクごとにトランザクションを閉じる。
  # 各段階の続きの位置は置き場から作り直すので、継続の情報を持たない新しいジョブ（Imports::Runs.reenqueue）でも続きから進む。
  # カーソルは、中断点で保存する進み具合の目安である
  class RunJob < ApplicationJob
    include ActiveJob::Continuable

    queue_as :imports
    # チャンクごとに Tenancy.with_tenant を開く。実行全体を包むと、終えたチャンクがコミットされない
    tenant_transaction :per_chunk
    # テナントごとに 1 つ。1 社が imports のワーカーを占めないための上限で、反映の正しさは取り込みと品目・在庫の行ロックが守る。
    # 上限が効くのは duration の間だけで、過ぎると待っているジョブが動きうる（solid_queue 1.7.0 の README「Concurrency controls」。
    # 既定は SolidQueue.default_concurrency_control_period の 3 分）。50,000 行の取り込みが終わる長さにする
    limits_concurrency to: 1, key: ->(_import_id, tenant_id) { tenant_id }, duration: 1.hour

    def perform(import_id, tenant_id)
      step(:stage) { |step| Staging.run(import_id, tenant_id) { step.set!(_1) } }
      step(:apply) do |step|
        while (row_number = Applying.next_chunk(import_id, tenant_id))
          step.set!(row_number)
        end
      end
      step(:finalize) { Finalizing.run(import_id, tenant_id) }
    end
  end
end
