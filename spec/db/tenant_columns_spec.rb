require "rails_helper"

# テナント列の列挙テスト（decisions.md 7 章）。テナントの表かどうかを、表を足した人の判断に任せない。
# owner_tenant_id を持たない表は、理由とともにここで宣言する。
RSpec.describe "テナント列" do
  EXEMPT_TABLES = {
    "tenants" => "テナントそのもの。取引先の名前を表示するため、どのテナントからも読める（data-model.md「取引関係と権限付与」）",
    "schema_migrations" => "Rails がマイグレーションの適用を記録する表。業務データを持たない",
    "ar_internal_metadata" => "Rails が DB の環境を記録する表。業務データを持たない"
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
