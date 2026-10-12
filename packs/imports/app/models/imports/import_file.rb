module Imports
  # 受注側が送った CSV のファイル。中身は取り込みを終えるか失敗したら消す（docs/architecture/data-model.md「取り込み（`imports`）」）
  class ImportFile < TenantRecord
    self.table_name = "import_files"
  end
end
