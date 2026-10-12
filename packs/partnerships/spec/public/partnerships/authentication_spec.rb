require "rails_helper"

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
