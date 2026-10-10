module Types
  # 請求書の状態。発行の時刻の有無から公開 API が決める
  class InvoiceStateType < BaseEnum
    graphql_name "InvoiceState"

    value "DRAFT", "下書き", value: :draft
    value "ISSUED", "発行済み", value: :issued
  end
end
