module Partnerships
  # 通知の宛先（docs/architecture/data-model.md「通知（`notifications`）」）。操作者の無いジョブから呼ぶので actor を取らず、
  # Tenancy.with_tenant の中で RLS の下で引く。別テナントのユーザーは含まない
  module Recipients
    # 自社の admin のユーザー ID
    def self.admin_ids
      Tenancy.require_tenant!
      User.where(role: "admin").order(:id).pluck(:id)
    end

    # ユーザー ID ごとのメールアドレス。消えたユーザーと別テナントのユーザーは含まない
    def self.emails(user_ids)
      Tenancy.require_tenant!
      User.where(id: user_ids).order(:id).pluck(:id, :email).to_h
    end
  end
end
