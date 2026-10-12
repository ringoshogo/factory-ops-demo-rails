module Imports
  # 取り込みのジョブのチャンクのトランザクション（docs/architecture/data-model.md「取り込み（`imports`）」）。
  # どの段階も、チャンクの初めに imports の行をロックし、ロックの後に置き場の状態を読み直してから書く。
  # 同じ取り込みのジョブが 2 つ動いても、2 つ目はロックを待ち、1 つ目が書いた後の状態から続けるので、結果は 1 つになる
  module Chunk
    # テナントのトランザクションを開いて取り込みの行をロックし、終えていなければブロックに渡してその値を返す。
    # 終えた取り込みと見えない取り込みでは、ブロックを呼ばずに nil を返す
    def self.locked(import_id, tenant_id)
      Tenancy.with_tenant(tenant_id) do
        import = Import.lock.find_by(id: import_id)
        yield import if import && !import.done?
      end
    end

    # 取り込み全体を失敗にし、ファイルの中身を消す。ロックした取り込みに対して呼ぶ
    def self.fail!(import, reason)
      import.update!(failed_at: Time.current, failure_reason: reason)
      finish!(import)
    end

    # 終えた取り込みのファイルの中身を消し、終わりのイベントを出す。ロックした取り込みに対して呼ぶ
    def self.finish!(import)
      # 中身を読まずに消す。行を読み込むと、10 MB の中身をメモリに載せる
      ImportFile.where(id: import.import_file_id).update_all(content: nil, updated_at: Time.current)
      Rails.event.notify("imports.finished", kind: import.kind, import_id: import.id, result: import.status.to_s,
        total_rows: import.total_rows, applied_rows: import.applied_rows, failed_rows: import.failed_rows,
        duration_ms: (((import.finished_at || import.failed_at) - import.created_at) * 1000).round)
    end
  end
end
