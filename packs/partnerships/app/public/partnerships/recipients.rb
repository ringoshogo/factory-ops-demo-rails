module Partnerships
  # 通知の宛先（docs/architecture/data-model.md「通知（`notifications`）」）。操作者の無いジョブから呼ぶので actor を取らない。
  # 操作者のいない入口の公開 API として、テナントの設定を求め、所有の条件を RLS に任せずに書き、ID と値だけを返す
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
  module Recipients
    # 自社の admin のユーザー ID
    def self.admin_ids
      own_users.where(role: "admin").order(:id).pluck(:id)
    end

    # ユーザー ID ごとのメールアドレス。消えたユーザーと別テナントのユーザーは含まない
    def self.emails(user_ids)
      own_users.where(id: user_ids).order(:id).pluck(:id, :email).to_h
    end

    def self.own_users
      Tenancy.require_tenant!
      User.where(owner_tenant_id: Current.tenant_id)
    end
    private_class_method :own_users
  end
end
