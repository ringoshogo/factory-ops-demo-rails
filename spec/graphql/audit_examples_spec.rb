require "rails_helper"

# audit を宣言した mutation は、監査の行の中身（対象と相手）を比べる example を持つ
# （docs/guides/testing.md「層への配分」）。宣言のラムダが対象か相手を取り違えても、
# 行の件数しか見ない example は落ちないので、action の文字列と、対象と相手の列の名前が同じ spec のファイルに現れることを確かめる
RSpec.describe "監査の行を比べる example" do
  def self.spec_globs = %w[spec/requests/**/*_spec.rb spec/scenarios/**/*_spec.rb spec/concurrency/**/*_spec.rb]

  def self.audited_actions(schema)
    schema.mutation.fields.values.filter_map { _1.mutation&.audit_action }.sort
  end

  # ファイルの名前と中身の組みから、action の文字列と、対象と相手の列の名前をすべて含むファイルを返す
  def self.comparing_files(action, sources)
    sources.select { |_, text| text.include?(%("#{action}")) && %w[target_id counterparty_tenant_id].all? { text.include?(_1) } }.keys
  end

  sources = spec_globs.flat_map { Dir[Rails.root.join(_1)] }.index_with { File.read(_1) }

  audited_actions(FactoryOpsSchema).each do |action|
    it "#{action} の監査の行の対象と相手を比べる example がある" do
      expect(self.class.comparing_files(action, sources)).not_to be_empty,
        "#{action} の行を引いて target_id と counterparty_tenant_id を比べる example を、#{self.class.spec_globs.join('・')} のどれかに書く"
    end
  end

  it "action の文字列があっても、対象と相手の列を見ないファイルは数えない" do
    # 外側の sources に代入すると、後に流れる example が見本の 2 ファイルだけを読むので、別の名前にする
    samples = { "count_spec.rb" => %(AuditLog.where(action: "x.do").count), "compare_spec.rb" => %("x.do" target_id counterparty_tenant_id) }

    expect(self.class.comparing_files("x.do", samples)).to eq([ "compare_spec.rb" ])
  end

  it "audit を宣言した mutation をスキーマから拾い、audit_exempt の mutation は拾わない" do
    expect(self.class.audited_actions(FactoryOpsSchema)).to include("purchase_order.place", "sales_order.cancel")
    expect(FactoryOpsSchema.mutation.fields.fetch("closeBillingPeriod").mutation.audit_action).to be_nil
  end
end
