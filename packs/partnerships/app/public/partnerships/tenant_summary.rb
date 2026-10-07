module Partnerships
  # 相手テナントについて見せてよいのは ID と名前だけ
  TenantSummary = Data.define(:id, :name)
end
