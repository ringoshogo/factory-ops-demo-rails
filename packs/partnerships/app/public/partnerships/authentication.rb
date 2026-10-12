module Partnerships
  # ログインと、セッションからの操作者の復元（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）
  module Authentication
    # session_version はセッションの世代。ログアウトとパスワードの変更で進み、前の世代のセッションを拒む
    Login = Data.define(:user_id, :tenant_id, :session_version)

    # ユーザーが見つからないときも同じだけ時間を掛け、メールアドレスの有無を応答時間から推測させない
    DUMMY_DIGEST = BCrypt::Password.create("dummy").to_s.freeze

    # テナントが決まる前なので、RLS の外で動く認証専用の関数 find_login_user で引く
    def self.authenticate(email:, password:)
      email = email.to_s.strip.downcase
      row = ApplicationRecord.with_connection do |c|
        c.select_one("SELECT * FROM find_login_user($1)", "Authentication", [ email ])
      end
      digest = row ? row["password_digest"] : DUMMY_DIGEST
      return unless password_matches?(digest, password) && row

      Login.new(user_id: row["id"], tenant_id: row["owner_tenant_id"], session_version: row["session_version"])
    end

    # Tenancy.with_tenant の中で呼ぶ。開いたテナントのユーザーだけを引くので、別テナントのユーザーは見つからない。
    # セッションの世代がユーザーの今の世代と違えば、ログアウトかパスワードの変更より前のセッションなので拒む
    def self.actor(user_id, session_version:)
      user = own_users.find_by(id: user_id)
      return unless user && user.session_version == session_version

      to_actor(user)
    end

    # Tenancy.with_tenant の中で呼ぶ。セッションを持たないジョブが、操作を依頼したユーザーとして公開 API を呼ぶときの操作者。
    # 役割は呼んだ時点の役割を読むので、依頼の後に admin でなくなったユーザーは member として返る。
    # 別テナントのユーザーと消えたユーザーは nil になる
    def self.acting_user(user_id)
      own_users.find_by(id: user_id)&.then { to_actor(_1) }
    end

    # Tenancy.with_tenant の中で呼ぶ。ユーザーの世代を進め、発行済みのすべてのセッションを使えなくする。
    # 世代が今のものと違うセッションでは進めない。無効になった Cookie で、他の端末のログインを切らせない
    def self.revoke_sessions(user_id, session_version:)
      own_users.where(id: user_id, session_version: session_version).update_all("session_version = session_version + 1")
    end

    # ログインの後の 3 つは操作者のいない入口の公開 API なので、テナントの設定を求め、所有の条件を RLS に任せずに書く
    # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
    def self.own_users
      Tenancy.require_tenant!
      User.where(owner_tenant_id: Current.tenant_id)
    end

    # 壊れたダイジェストもパスワード違いと同じに扱い、同じだけ時間を掛ける
    def self.password_matches?(digest, password)
      BCrypt::Password.new(digest).is_password?(password.to_s)
    rescue BCrypt::Errors::InvalidHash
      BCrypt::Password.new(DUMMY_DIGEST).is_password?(password.to_s)
      false
    end

    def self.to_actor(user)
      Actor.new(user_id: user.id, tenant_id: user.owner_tenant_id, name: user.name, email: user.email, role: user.role,
        partner_code: Tenant.find(user.owner_tenant_id).partner_code)
    end
    private_class_method :own_users, :password_matches?, :to_actor
  end
end
