require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# セッションを持たないジョブの操作者（docs/adr/007 決定 5 の A-4）。取り込みのジョブは、取り込みを始めたユーザーとして
# 公開 API を呼ぶ。役割は、ジョブが呼んだ時点のユーザーの役割を読む
RSpec.describe Partnerships::Authentication, ".acting_user" do
  let(:tenant) { FactoryBot.create(:tenant) }
  let(:other) { FactoryBot.create(:tenant) }
  let!(:admin) { Tenancy.with_tenant(tenant.id) { FactoryBot.create(:user, :admin) } }
  let!(:stranger) { Tenancy.with_tenant(other.id) { FactoryBot.create(:user, :admin) } }

  it "自社のユーザーを、いまの役割と取引用コードを持つ操作者にする" do
    actor = Tenancy.with_tenant(tenant.id) { described_class.acting_user(admin.id) }

    expect(actor).to have_attributes(user_id: admin.id, tenant_id: tenant.id, role: "admin", partner_code: tenant.partner_code)
  end

  it "役割が変わった後は、変わった後の役割で返す" do
    Tenancy.with_tenant(tenant.id) { admin.update!(role: "member") }

    expect(Tenancy.with_tenant(tenant.id) { described_class.acting_user(admin.id) }.role).to eq("member")
  end

  it "別テナントのユーザーと存在しないユーザーは nil" do
    expect(Tenancy.with_tenant(tenant.id) { [ described_class.acting_user(stranger.id), described_class.acting_user(SecureRandom.uuid) ] })
      .to eq([ nil, nil ])
    # 対照：同じユーザーは、自社のテナントでは引ける
    expect(Tenancy.with_tenant(other.id) { described_class.acting_user(stranger.id) }&.user_id).to eq(stranger.id)
  end
end

# セッションからの操作者の復元・ジョブの操作者・セッションの失効は、操作者のいない入口の公開 API なので、開いたテナントの
# ユーザーだけを、所有の条件を RLS に任せずに引く（docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
RSpec.describe Partnerships::Authentication, "の操作者のいない入口" do
  include_context "RLS の SELECT を開く"

  let(:tenant) { FactoryBot.create(:tenant) }
  let(:other) { FactoryBot.create(:tenant) }
  let!(:admin) { Tenancy.with_tenant(tenant.id) { FactoryBot.create(:user, :admin) } }
  let!(:stranger) { Tenancy.with_tenant(other.id) { FactoryBot.create(:user, :admin) } }

  # セッションの失効（revoke_sessions）は UPDATE で、SELECT を開いても RLS の UPDATE のポリシーが他社の行を除くので、ここでは確かめない
  it "RLS の SELECT を開いても、他社のユーザーを操作者にしない" do
    Tenancy.with_tenant(tenant.id) do
      cross_read!
      # 対照：開いた後は、他社のユーザーが SELECT で見え、自社のユーザーは操作者になる
      expect(Partnerships::User.where(id: stranger.id).exists?).to be(true)
      expect(described_class.actor(admin.id, session_version: 0)&.user_id).to eq(admin.id)

      expect([ described_class.actor(stranger.id, session_version: 0), described_class.acting_user(stranger.id) ]).to eq([ nil, nil ])
    end
  end

  it "テナントを開かずに呼ぶと例外にする" do
    expect { described_class.actor(admin.id, session_version: 0) }.to raise_error(Tenancy::MissingTenant)
    expect { described_class.acting_user(admin.id) }.to raise_error(Tenancy::MissingTenant)
    expect { described_class.revoke_sessions(admin.id, session_version: 0) }.to raise_error(Tenancy::MissingTenant)
  end
end
