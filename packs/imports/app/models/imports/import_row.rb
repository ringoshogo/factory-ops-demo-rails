module Imports
  # 置き場の行。data は見出しの順の値の配列で、applied_at（反映した）か error（失敗した）のどちらか 1 つを結果に持つ
  class ImportRow < TenantRecord
    self.table_name = "import_rows"

    belongs_to :import

    scope :pending, -> { where(applied_at: nil, error: nil) }
    scope :failed, -> { where.not(error: nil) }
  end
end
