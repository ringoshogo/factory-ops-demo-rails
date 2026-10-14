require "rails_helper"

# 一覧の検索の語（docs/architecture/graphql-schema.md「ページングと N+1」）。品目の一覧と在庫の一覧が同じ規則で検索するので、
# 規則は基盤が持つ監査ログの表の 2 つの文字列の列で確かめる
RSpec.describe Keyword do
  let!(:tenant) { FactoryBot.create(:tenant) }

  # action と target_type の組で行を作る
  def create_logs(*pairs)
    Tenancy.with_tenant(tenant.id) { pairs.each { |action, target_type| FactoryBot.create(:audit_log, action:, target_type:) } }
  end

  def search(keyword)
    Tenancy.with_tenant(tenant.id) do
      described_class.search(AuditLog.all, keyword, AuditLog.arel_table[:action], AuditLog.arel_table[:target_type])
        .order(:action).pluck(:action)
    end
  end

  it "前後の空白（全角を含む）を除き、どれかの列に含む行に、大文字と小文字を区別せずに絞る。空なら絞らない" do
    create_logs([ "BOLT-8", "六角ボルト" ], [ "nut-1", "Bolt 用ナット" ], [ "W-1", "ワッシャー" ])

    expect(search("  bolt　")).to eq(%w[BOLT-8 nut-1])
    expect(search("ボルト")).to eq(%w[BOLT-8])
    expect(search("NUT")).to eq(%w[nut-1])
    expect([ " ", "", nil ].map { search(_1).size }).to eq([ 3, 3, 3 ])
  end

  it "% と _ と \\ は、ワイルドカードではなく文字として扱う" do
    create_logs(*[ "50%OFF", "A_1", "A\\1", "AB1", "500FF" ].map { [ _1, "品目" ] })

    expect(search("%")).to eq(%w[50%OFF])
    expect(search("_")).to eq(%w[A_1])
    expect(search("\\")).to eq([ "A\\1" ])
    # 対照：ワイルドカードでない文字は、そのまま部分一致で絞る
    expect(search("A")).to contain_exactly("A\\1", "AB1", "A_1")
  end
end
