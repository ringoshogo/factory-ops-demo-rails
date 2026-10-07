module Partnerships
  # 操作者。公開 API とリゾルバは、モデルではなくこの値を受け渡す
  Actor = Data.define(:user_id, :tenant_id, :name, :email, :role)
end
