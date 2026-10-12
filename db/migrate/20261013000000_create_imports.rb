class CreateImports < ActiveRecord::Migration[8.1]
  include TenantTable

  # 取り込みのファイル・取り込み・置き場の行（docs/architecture/data-model.md「取り込み（`imports`）」、docs/adr/007 決定 5 の A-4）
  def change
    create_tenant_table :import_files, comment: "[取り込み] 受注側が送った CSV のファイル。取り込みを終えたら中身を消す" do |t|
      t.string :filename, null: false
      t.integer :byte_size, null: false
      t.binary :content
      t.uuid :uploaded_by_user_id, null: false
      t.timestamps

      # 上限は Imports::Files::MAX_BYTES と同じ値。置き場を読む stage は中身を 1 度に読むので、メモリをこの大きさで抑える
      t.check_constraint "byte_size BETWEEN 0 AND 10485760", name: "import_files_byte_size_limit"
      t.check_constraint "content IS NULL OR octet_length(content) = byte_size", name: "import_files_content_size"
    end

    create_tenant_table :imports, comment: "[取り込み] ファイルごとの取り込み。状況は時刻列と件数から導出する" do |t|
      t.string :kind, null: false
      t.integer :total_rows
      t.integer :applied_rows, null: false, default: 0
      t.integer :failed_rows, null: false, default: 0
      t.datetime :started_at
      t.datetime :staged_at
      t.datetime :finished_at
      t.datetime :failed_at
      t.string :failure_reason
      t.uuid :requested_by_user_id, null: false
      t.timestamps

      t.check_constraint "kind::text IN ('items', 'stocks')", name: "imports_kind"
      t.check_constraint "(failed_at IS NULL) = (failure_reason IS NULL)", name: "imports_failure_reason"
      t.check_constraint "applied_rows >= 0 AND failed_rows >= 0", name: "imports_counts_not_negative"
    end
    add_tenant_reference :imports, :import_files
    # 1 つのファイルの取り込みは 1 回。startImport の 2 回目は CONFLICT になる
    add_index :imports, :import_file_id, unique: true

    create_tenant_table :import_rows, comment: "[取り込み] 置き場の行。CSV の 1 行の値と、反映の結果を持つ" do |t|
      t.integer :row_number, null: false
      # 見出しの順の値の配列。1 列目が品目コードで、同じファイルの 2 行目以降の同じコードを、この値で探す
      t.jsonb :data, null: false
      t.datetime :applied_at
      t.string :error
      t.timestamps

      t.check_constraint "applied_at IS NULL OR error IS NULL", name: "import_rows_single_result"
    end
    add_tenant_reference :import_rows, :imports
    add_index :import_rows, [ :import_id, :row_number ], unique: true
    # 結果の無い行を行番号の順に取る apply と、失敗した行を返す rowErrors が使う
    add_index :import_rows, [ :import_id, :row_number ], where: "applied_at IS NULL AND error IS NULL", name: "index_import_rows_pending"
    add_index :import_rows, [ :import_id, :row_number ], where: "error IS NOT NULL", name: "index_import_rows_failed"
  end
end
