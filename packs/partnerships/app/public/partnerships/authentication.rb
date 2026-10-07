module Partnerships
  # ログインと、セッションからの操作者の復元（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
  module Authentication
    Login = Data.define(:user_id, :tenant_id)

    # ユーザーが見つからないときも同じだけ時間を掛け、メールアドレスの有無を応答時間から推測させない
    DUMMY_DIGEST = BCrypt::Password.create("dummy").to_s.freeze

    # テナントが決まる前なので、RLS の外で動く認証専用の関数 find_login_user で引く
    def self.authenticate(email:, password:)
      email = email.to_s.strip.downcase
      row = ApplicationRecord.with_connection do |c|
        c.select_one("SELECT * FROM find_login_user($1)", "Authentication", [ email ])
      end
      digest = row ? row["password_digest"] : DUMMY_DIGEST
      return unless BCrypt::Password.new(digest).is_password?(password.to_s) && row

      Login.new(user_id: row["id"], tenant_id: row["owner_tenant_id"])
    end

    # Tenancy.with_tenant の中で呼ぶ。RLS の下で引くので、別テナントのユーザーは見つからない
    def self.actor(user_id)
      user = User.find_by(id: user_id)
      user && Actor.new(user_id: user.id, tenant_id: user.owner_tenant_id, name: user.name, email: user.email, role: user.role)
    end
  end
end
