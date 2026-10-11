require "rails_helper"

# テナント列の列挙テスト（decisions.md 7 章）。テナントの表かどうかを、表を足した人の判断に任せない。
# owner_tenant_id を持たない表は、理由とともにここで宣言する。
RSpec.describe "テナント列" do
  EXEMPT_TABLES = {
    "tenants" => "テナントそのもの。取引先の名前を表示するため、どのテナントからも読める（data-model.md「取引関係と権限付与（`partnerships`）」）",
    "schema_migrations" => "Rails がマイグレーションの適用を記録する表。業務データを持たない",
    "ar_internal_metadata" => "Rails が DB の環境を記録する表。業務データを持たない",
    "webhook_inbox_events" => "外部の Webhook の受信。届いた時点ではテナントが決まらず、処理のジョブが送信のときに付けたテナントで " \
      "送信記録を書く。メールアドレスを除いて書き、処理を終えた行は 30 日で消す（adr/007 決定 5 の A-3）",
    **%w[
      solid_queue_jobs solid_queue_ready_executions solid_queue_scheduled_executions solid_queue_claimed_executions
      solid_queue_blocked_executions solid_queue_failed_executions solid_queue_recurring_executions
      solid_queue_recurring_tasks solid_queue_pauses solid_queue_processes solid_queue_semaphores
      solid_queue_batches solid_queue_batch_executions
    ].index_with { "Solid Queue の表。全テナントのジョブを 1 つのキューで扱う基盤で、引数はテナント ID と伝票の ID だけを運ぶ（adr/005 決定 5）" }
  }.freeze

  let(:connection) { ActiveRecord::Base.lease_connection }

  it "すべての表が owner_tenant_id を持つか、除外の理由を宣言している" do
    missing = connection.tables.reject do |table|
      connection.column_exists?(table, :owner_tenant_id) || EXEMPT_TABLES.key?(table)
    end

    expect(missing).to be_empty
  end

  it "除外した表は owner_tenant_id を持たず、実在する" do
    expect(EXEMPT_TABLES.keys.select { |table| connection.column_exists?(table, :owner_tenant_id) }).to be_empty
    expect(EXEMPT_TABLES.keys - connection.tables).to be_empty
  end

  it "owner_tenant_id を持つ表のモデルは TenantRecord を継承する" do
    Rails.application.eager_load!
    models = ApplicationRecord.descendants.reject(&:abstract_class?).select { |model| model.name&.safe_constantize == model }

    offenders = models.select do |model|
      connection.column_exists?(model.table_name, :owner_tenant_id) && !(model < TenantRecord)
    end

    expect(offenders).to be_empty
  end
end
