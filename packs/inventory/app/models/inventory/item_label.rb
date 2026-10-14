module Inventory
  # 受注の品目のコードと名前の写し。在庫の一覧を並べ、検索するためだけに持ち、書くのは ItemLabels.put だけである
  # （docs/architecture/data-model.md「在庫（`inventory`）」）
  class ItemLabel < TenantRecord
  end
end
