require "rails_helper"

# 自社の監査ログを新しいものから読み、条件で絞る（docs/architecture/graphql-schema.md「監査ログ」）
RSpec.describe Platform::AuditLogs do
  let!(:tenant) { FactoryBot.create(:tenant) }
  let!(:other) { FactoryBot.create(:tenant) }
  # 基盤は取引関係に依存しないので、操作者の値はテナント ID だけを持つ値で代える
  let(:actor) { Data.define(:tenant_id).new(tenant_id: tenant.id) }

  def create_log(tenant_id = tenant.id, **attributes)
    Tenancy.with_tenant(tenant_id) { FactoryBot.create(:audit_log, **attributes) }
  end

  def list(**options)
    Tenancy.with_tenant(tenant.id) { described_class.list(actor, first: 10, after: nil, **options) }
  end

  it "自社の行だけを、新しいものから返す" do
    older, newer = Array.new(2) { create_log }
    create_log(other.id)

    expect(list.values.map(&:id)).to eq([ newer.id, older.id ])
  end

  # RLS も他社の行を閉じるので、上の example は scope の条件を外しても通る。条件そのものを確かめる
  it "scope は RLS に任せず、所有テナントの条件を持つ" do
    scope = Tenancy.with_tenant(tenant.id) do
      Platform::AuditLogPolicy.new(user: actor).apply_scope(AuditLog.all, type: :active_record_relation, name: :own)
    end

    expect(scope.where_values_hash).to eq("owner_tenant_id" => tenant.id)
  end

  it "first と after でページを送る" do
    logs = Array.new(3) { create_log }.reverse
    first_page = Tenancy.with_tenant(tenant.id) { described_class.list(actor, first: 2, after: nil) }
    second_page = Tenancy.with_tenant(tenant.id) { described_class.list(actor, first: 2, after: first_page.cursors.last) }

    expect([ first_page.values.map(&:id), first_page.has_next_page ]).to eq([ logs.first(2).map(&:id), true ])
    expect([ second_page.values.map(&:id), second_page.has_next_page ]).to eq([ [ logs.last.id ], false ])
  end

  it "action と相関 ID の一致で絞る" do
    target = create_log(action: "purchase_order.place", correlation_id: "c-1")
    create_log(action: "purchase_order.place", correlation_id: "c-2")
    create_log(action: "item.save", correlation_id: "c-1")

    expect(list(filter: { action: "purchase_order.place", correlation_id: "c-1" }).values.map(&:id)).to eq([ target.id ])
  end

  it "時刻は occurred_from 以上・occurred_to 未満で絞る" do
    at = Time.zone.parse("2026-10-10 09:00")
    logs = [ at - 1.second, at, at + 1.hour - 1.second, at + 1.hour ].map { create_log(occurred_at: _1) }

    expect(list(filter: { occurred_from: at, occurred_to: at + 1.hour }).values.map(&:id)).to eq(logs[1..2].reverse.map(&:id))
  end
end
