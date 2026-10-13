module Partnerships
  # テナントと、その admin・member のユーザーを作る。シードと E2E の世界の準備のためのもので、サインアップの入口ではない。
  # テナントがまだ無いので操作者を取らず、テナントの設定の外で呼ぶ。操作者のいない入口の規則のうち、Tenancy.require_tenant! だけを
  # 通さない例外で、ユーザーは作ったテナントの Tenancy.with_tenant の中で書く
  # （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」、docs/architecture/data-model.md「RLS」）。
  # 本番の環境では、DEMO_WORLD_ENABLED=1 を渡したプロセスでだけ呼べる（Platform::DemoWorldGate）。本番のテナントとユーザーを、
  # デモの手元の値で作らないためである
  module Onboarding
    class ProductionEnvironment < StandardError; end

    # users は { email:, name:, role:, password: } の配列。テナントとユーザーを 1 つのトランザクションで書き、テナントの ID を返す。
    # 同じ code・partner_code のテナントと、同じメールアドレスのユーザーは一意索引が拒み、何も残さない
    def self.register(name:, code:, partner_code:, users:)
      refuse_production!
      raise ArgumentError, "Partnerships::Onboarding.register はテナントの設定の外で呼ぶ" if Current.tenant_id.present?

      ApplicationRecord.transaction(requires_new: true) do
        tenant = Tenant.create!(name:, code:, partner_code:)
        Tenancy.with_tenant(tenant.id) do
          users.each do |user|
            # 所有テナントは作ったテナントに決まるので、ほかの項目（owner_tenant_id など）を受け付けない
            raise ArgumentError, "users の項目は email・name・role・password だけにする" unless user.keys.sort == %i[email name password role]

            User.create!(owner_tenant_id: tenant.id, **user)
          end
        end
        tenant.id
      end
    end

    # code のテナントの ID。無ければ nil。シードと E2E の世界が、作った世界をもう一度作らないために引く
    def self.tenant_id(code:)
      refuse_production!
      Tenant.where(code:).pick(:id)
    end

    def self.refuse_production!
      raise ProductionEnvironment, "Partnerships::Onboarding は本番の環境では DEMO_WORLD_ENABLED=1 のときだけ呼べる" unless Platform::DemoWorldGate.open?
    end
    private_class_method :refuse_production!
  end
end
