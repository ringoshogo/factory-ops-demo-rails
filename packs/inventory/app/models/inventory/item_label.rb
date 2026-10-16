module Inventory
  # 受注の品目のコードと名前の写し。在庫の一覧を並べ、検索するためと、調整と在庫数の設定が自社の品目かを確かめるために持ち、
  # 書くのは ItemLabels.put だけである
  # （docs/architecture/data-model.md「在庫（`inventory`）」）
  class ItemLabel < TenantRecord
  end
end
