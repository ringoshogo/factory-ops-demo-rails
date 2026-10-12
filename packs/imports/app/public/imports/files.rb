module Imports
  # 取り込むファイルを置く（POST /imports/files）。置くだけで、業務の表には何も起きない
  module Files
    # import_files の CHECK 制約と同じ値。業務 DB の bytea に置くファイルの大きさを抑える
    MAX_BYTES = 10 * 1024 * 1024
    MAX_FILENAME_LENGTH = 255
    # 置いてからこの時間を過ぎても取り込みを始めないファイルの中身を、定期のジョブが消す。置いたその日のうちに
    # 取り込む使い方を妨げず、受け口に件数の上限が無くても業務 DB の bytea が増え続けないようにする長さである
    ABANDONED_AFTER = 24.hours

    def self.store(actor, filename:, content:)
      if content.bytesize > MAX_BYTES
        return OperationResult.failure(:invalid_input, path: [ :file ], message: "File must be at most #{MAX_BYTES} bytes")
      end

      file = ImportFile.create!(owner_tenant_id: actor.tenant_id, filename: File.basename(filename.to_s)[0, MAX_FILENAME_LENGTH],
        byte_size: content.bytesize, content:, uploaded_by_user_id: actor.user_id)
      OperationResult.success(ImportFileValue.new(id: file.id, filename: file.filename, byte_size: file.byte_size))
    end

    # 開いたテナントの、置いてから ABANDONED_AFTER を過ぎても取り込みを始めないファイルの中身を消し、消した件数を返す
    # （docs/architecture/data-model.md「取り込み（`imports`）」）。操作者のいない入口から呼ぶので、テナントの設定を求め、
    # 所有の条件を RLS に任せずに書く（docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）。
    # 候補の行をロックしてから、取り込みが無いことを別の文で確かめ直す。READ COMMITTED は文ごとにスナップショットを取り直すので、
    # ロックを待つ間にコミットした Runs.start の取り込みは 2 つ目の文に見える。ロックの文の条件だけでは、ロックを待った後に
    # 読み直すのは行そのものだけで、取り込みの有無は読み直さない
    def self.purge_abandoned
      Tenancy.require_tenant!
      not_started = "NOT EXISTS (SELECT 1 FROM imports WHERE imports.import_file_id = import_files.id)"
      ids = ImportFile.where(owner_tenant_id: Current.tenant_id).where.not(content: nil)
        .where(created_at: ...ABANDONED_AFTER.ago).where(not_started).order(:id).lock.pluck(:id)
      return 0 if ids.empty?

      ImportFile.where(owner_tenant_id: Current.tenant_id, id: ids).where(not_started).update_all(content: nil, updated_at: Time.current)
    end
  end
end
