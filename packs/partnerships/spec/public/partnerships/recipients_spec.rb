require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 通知の宛先。操作者のいない入口の公開 API なので、開いたテナントのユーザーだけを、所有の条件を RLS に任せずに引く
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」）
RSpec.describe Partnerships::Recipients do
  include_context "RLS の SELECT を開く"

  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:other) { FactoryBot.create(:tenant).id }
  let!(:admin) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user, :admin) } }
  let!(:member) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user) } }
  let!(:stranger) { Tenancy.with_tenant(other) { FactoryBot.create(:user, :admin) } }

  def tenancy(&) = Tenancy.with_tenant(tenant, &)

  it "自社の admin の ID と、自社のユーザーのメールアドレスを返す" do
    expect(tenancy { described_class.admin_ids }).to eq([ admin.id ])
    expect(tenancy { described_class.emails([ admin.id, member.id ]) }).to eq(admin.id => admin.email, member.id => member.email)
  end

  it "RLS の SELECT を開いても、他社のユーザーを含めない" do
    tenancy do
      cross_read!
      # 対照：開いた後は、他社の admin が SELECT で見える
      expect(Partnerships::User.where(role: "admin").pluck(:id)).to include(stranger.id)

      expect(described_class.admin_ids).to eq([ admin.id ])
      expect(described_class.emails([ admin.id, stranger.id ])).to eq(admin.id => admin.email)
    end
  end

  it "テナントを開かずに呼ぶと例外にする" do
    expect { described_class.admin_ids }.to raise_error(Tenancy::MissingTenant)
    expect { described_class.emails([ admin.id ]) }.to raise_error(Tenancy::MissingTenant)
  end
end
