require "rails_helper"

# 公開 API が別のコンテキストの SQL へ値を渡す副問い合わせ（docs/adr/010-状況の導出をSQLの式1つにする.md 決定 2）
RSpec.describe SqlSubquery do
  let(:tenant) { FactoryBot.create(:tenant) }

  around { |example| TenantExample.run(example, tenant.id) }

  describe "#contains" do
    it "役割の列の値に含まれる行だけを残し、含まれない値の行を除く" do
      kept, other, dropped = Array.new(3) { FactoryBot.create(:audit_log) }
      subquery = SqlSubquery.of(AuditLog.where(id: [ kept.id, other.id ]).select(:target_id), target: "target_id")
      logs = AuditLog.arel_table

      # 対照：絞らなければ 3 行とも返る
      expect(AuditLog.pluck(:id)).to contain_exactly(kept.id, other.id, dropped.id)
      expect(AuditLog.where(subquery.contains(:target, logs[:target_id])).pluck(:id)).to contain_exactly(kept.id, other.id)
      expect(AuditLog.where.not(subquery.contains(:target, logs[:target_id])).pluck(:id)).to eq([ dropped.id ])
    end

    it "結ぶ側の行の数を変えない" do
      log = FactoryBot.create(:audit_log)
      FactoryBot.create(:audit_log, target_id: log.target_id)
      subquery = SqlSubquery.of(AuditLog.select(:target_id), target: "target_id")

      expect(AuditLog.where(id: log.id).where(subquery.contains(:target, AuditLog.arel_table[:target_id])).count).to eq(1)
    end
  end
end
