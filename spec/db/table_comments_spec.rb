require "rails_helper"

# 全表に、コンテキストの接頭辞で始まる 1 行の説明（COMMENT ON TABLE）があることを、テスト DB のカタログで確かめる。
# 書式は docs/architecture/data-model.md「全テーブルに共通の規則」。
RSpec.describe "表の説明" do
  PREFIXES = %w[取引関係 購買 受注 在庫 出荷 請求 イベント 基盤 キュー].freeze

  let(:comments) do
    ActiveRecord::Base.lease_connection.select_rows(<<~SQL).to_h
      SELECT relname, obj_description(oid, 'pg_class') FROM pg_class
      WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'p')
      ORDER BY relname
    SQL
  end

  it "表がある" do
    expect(comments).to include("users")
  end

  it "どの表にも説明がある" do
    expect(comments.select { |_table, comment| comment.blank? }.keys).to be_empty
  end

  it "説明は 1 行で、一覧にある接頭辞から始まる" do
    format = /\A\[(?:#{PREFIXES.join("|")})\] \S[^\n]*\z/
    malformed = comments.reject { |_table, comment| comment.blank? || comment.match?(format) }

    expect(malformed).to be_empty
  end
end
