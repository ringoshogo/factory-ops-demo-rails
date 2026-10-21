module Imports
  # ファイルごとの取り込み。状況は時刻列と件数から優先順で導出する（docs/architecture/data-model.md「取り込み（`imports`）」）
  class Import < TenantRecord
    self.table_name = "imports"

    belongs_to :import_file

    def status
      if failed_at then :failed
      elsif finished_at then failed_rows.positive? ? :partially_failed : :succeeded
      elsif staged_at then :applying
      elsif started_at then :staging
      else :queued
      end
    end

    # 終えた取り込みには、どの段階も何も書かない
    def done? = finished_at.present? || failed_at.present?
  end
end
