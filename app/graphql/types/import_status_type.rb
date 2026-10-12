module Types
  # 公開 API が時刻列と件数から導出した取り込みの状況（docs/architecture/data-model.md「取り込み（`imports`）」）
  class ImportStatusType < BaseEnum
    graphql_name "ImportStatus"

    value "FAILED", "失敗", value: :failed
    value "PARTIALLY_FAILED", "一部失敗", value: :partially_failed
    value "SUCCEEDED", "完了", value: :succeeded
    value "APPLYING", "反映中", value: :applying
    value "STAGING", "置き場へ写し中", value: :staging
    value "QUEUED", "待機中", value: :queued
  end
end
