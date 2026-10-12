module Imports
  # 取り込みの依頼。置いたファイルと、利用者が選んだ種類の組で、取り込みの開始の規則（ImportPolicy#start?）が種類を見る対象になる
  ImportRequestValue = Data.define(:file_id, :owner_tenant_id, :kind)
end
