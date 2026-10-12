require "rails_helper"

# ジョブのテナントのトランザクションの単位（docs/adr/007 決定 5 の A-4）。既定は実行全体を、作った時点のテナントの
# Tenancy.with_tenant で包む。tenant_transaction :per_chunk を宣言したジョブは包まず、ジョブがチャンクごとに開く
RSpec.describe ApplicationJob, ".tenant_transaction" do
  let(:tenant_id) { FactoryBot.create(:tenant).id }

  before do
    stub_const("TenantTransactionSpecSeen", [])
    stub_const("PerJobSpecJob", Class.new(described_class) do
      def perform = TenantTransactionSpecSeen << [ Current.tenant_id, ApplicationRecord.connection.open_transactions ]
    end)
    stub_const("PerChunkSpecJob", Class.new(described_class) do
      tenant_transaction :per_chunk

      def perform = TenantTransactionSpecSeen << [ Current.tenant_id, ApplicationRecord.connection.open_transactions ]
    end)
  end

  # example のトランザクションが 1 段あるので、包んだジョブの中では 2 段になる
  it "既定のジョブは実行全体をテナントのトランザクションで包み、:per_chunk を宣言したジョブは包まない" do
    base = ApplicationRecord.connection.open_transactions
    [ PerJobSpecJob, PerChunkSpecJob ].each { |job| Tenancy.with_tenant(tenant_id) { job.new }.perform_now }

    expect(TenantTransactionSpecSeen).to eq([ [ tenant_id, base + 1 ], [ nil, base ] ])
  end

  it "決めた 2 つのほかの単位は、クラスの読み込みで止める" do
    expect { Class.new(described_class) { tenant_transaction :per_row } }.to raise_error(ArgumentError, /per_row/)
  end
end
