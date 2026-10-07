module Partnerships
  # 取引関係の値。supplier・buyer は TenantSummary、permissions は付与された権限の文字列の配列
  PartnershipValue = Data.define(:id, :supplier, :buyer, :status, :revoked_at, :permissions)
end
