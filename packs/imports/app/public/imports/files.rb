module Imports
  # 取り込むファイルを置く（POST /imports/files）。置くだけで、業務の表には何も起きない
  module Files
    # import_files の CHECK 制約と同じ値。業務 DB の bytea に置くファイルの大きさを抑える
    MAX_BYTES = 10 * 1024 * 1024
    MAX_FILENAME_LENGTH = 255

    def self.store(actor, filename:, content:)
      if content.bytesize > MAX_BYTES
        return OperationResult.failure(:invalid_input, path: [ :file ], message: "File must be at most #{MAX_BYTES} bytes")
      end

      file = ImportFile.create!(owner_tenant_id: actor.tenant_id, filename: File.basename(filename.to_s)[0, MAX_FILENAME_LENGTH],
        byte_size: content.bytesize, content:, uploaded_by_user_id: actor.user_id)
      OperationResult.success(ImportFileValue.new(id: file.id, filename: file.filename, byte_size: file.byte_size))
    end
  end
end
