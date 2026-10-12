module Imports
  # 置き場へ写す段階（docs/adr/007 決定 5 の A-4）。ファイルを先頭から 1 行ずつ読み、置き場に無い行をチャンクごとに書く。
  # 置き場の最大の行番号が続きの位置なので、継続の情報を持たないジョブでも続きから書く
  module Staging
    CHUNK_ROWS = 1_000
    # 見出しを除いた行の数の上限。超えたファイルは、写した行があっても取り込み全体を失敗にする
    MAX_ROWS = 50_000
    # 行番号は、見出しを 1 行目とした CSV の記録の番号。利用者が表計算のソフトで開いたときの行と合う
    FIRST_ROW_NUMBER = 2
    # ファイルの中身を、この大きさの断片ずつ DB から一時ファイルへ写してから読む。bytea を 1 度に読むと、受け取った 16 進の文字列と
    # 復号した文字列が同時に載り、ワーカーのメモリがファイルの数倍になる
    SLICE_BYTES = 1024 * 1024

    # チャンクを書くたびに、書き終えた行番号を yield する。呼ぶ側はそこを中断点にする
    def self.run(import_id, tenant_id)
      kind, file_id, byte_size, staged = Chunk.locked(import_id, tenant_id) do |import|
        import.update!(started_at: Time.current) unless import.started_at
        next if import.staged_at

        [ import.kind, import.import_file_id, ImportFile.where(id: import.import_file_id).pick(:byte_size),
          ImportRow.where(import_id:).maximum(:row_number) || 0 ]
      end
      return unless kind

      with_file(tenant_id, file_id, byte_size) do |io|
        csv = CSV.new(io)
        return fail(import_id, tenant_id, "header_mismatch") unless CsvContract.header?(kind, csv.shift)

        buffer = []
        csv.each.with_index(FIRST_ROW_NUMBER) do |values, row_number|
          return fail(import_id, tenant_id, "too_many_rows") if row_number - FIRST_ROW_NUMBER >= MAX_ROWS
          next if row_number <= staged

          buffer << [ row_number, values ]
          next if buffer.size < CHUNK_ROWS

          write(import_id, tenant_id, buffer)
          buffer = []
          yield row_number
        end
        write(import_id, tenant_id, buffer)
      end
      finish(import_id, tenant_id)
    rescue CSV::InvalidEncodingError
      fail(import_id, tenant_id, "invalid_encoding")
    rescue CSV::MalformedCSVError
      fail(import_id, tenant_id, "malformed_csv")
    end

    # ファイルの中身を一時ファイルに写し、UTF-8 として開いて渡す。表計算のソフトが付ける BOM は、開くときに読み飛ばす
    def self.with_file(tenant_id, file_id, byte_size, &)
      Tempfile.create([ "import", ".csv" ], binmode: true) do |file|
        (0...byte_size).step(SLICE_BYTES) do |offset|
          file.write(Tenancy.with_tenant(tenant_id) do
            ImportFile.where(id: file_id).pick(Arel.sql("substring(content FROM #{offset + 1} FOR #{SLICE_BYTES})"))
          end)
        end
        file.flush
        File.open(file.path, "r:bom|utf-8", &)
      end
    end

    # ロックの後に最大の行番号を読み直し、それより後の行だけを書く。値は前後の空白を除いた文字列にする
    def self.write(import_id, tenant_id, buffer)
      return if buffer.empty?

      Chunk.locked(import_id, tenant_id) do |import|
        staged = ImportRow.where(import_id:).maximum(:row_number) || 0
        rows = buffer.select { |row_number, _| row_number > staged }.map do |row_number, values|
          { owner_tenant_id: import.owner_tenant_id, import_id:, row_number:, data: values.map { _1.to_s.strip } }
        end
        ImportRow.insert_all(rows, unique_by: %i[import_id row_number]) if rows.any?
      end
    end

    def self.finish(import_id, tenant_id)
      Chunk.locked(import_id, tenant_id) do |import|
        import.update!(staged_at: Time.current, total_rows: ImportRow.where(import_id:).count) unless import.staged_at
      end
    end

    def self.fail(import_id, tenant_id, reason)
      Chunk.locked(import_id, tenant_id) { |import| Chunk.fail!(import, reason) }
      nil
    end

    private_class_method :with_file, :write, :finish, :fail
  end
end
