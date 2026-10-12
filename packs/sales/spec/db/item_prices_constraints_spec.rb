require "rails_helper"

# 単価の行を DB が守る規則（docs/adr/006 決定 2・3、docs/architecture/data-model.md「受注（`sales`）」）。
# 現在の行同士は同じ品目で有効期間が重ならず、行は現在の行の記録期間を閉じる以外に変えられない
RSpec.describe "item_prices の制約" do
  let(:supplier) { FactoryBot.create(:tenant) }
  let!(:item) { FactoryBot.create(:item, unit_price: nil) }

  around { |example| Tenancy.with_tenant(supplier.id) { example.run } }

  def connection = ActiveRecord::Base.lease_connection

  def insert(valid_period: "(,)", recorded_period: "[2026-10-01 00:00:00+00,)", unit_price: 100)
    connection.select_value(<<~SQL)
      INSERT INTO item_prices (owner_tenant_id, item_id, unit_price, valid_period, recorded_period)
      VALUES (#{connection.quote(supplier.id)}, #{connection.quote(item.id)}, #{unit_price},
        #{connection.quote(valid_period)}, #{connection.quote(recorded_period)})
      RETURNING id
    SQL
  end

  def update(id, assignment) = connection.execute("UPDATE item_prices SET #{assignment} WHERE id = #{connection.quote(id)}")

  def close(id, at = "2026-10-05 00:00:00+00") = update(id, "recorded_period = tstzrange(lower(recorded_period), #{connection.quote(at)})")

  describe "排他制約" do
    it "現在の行同士で有効期間が重なると拒み、重ならない行と、閉じた行との重なりは通す" do
      first = insert(valid_period: "[,2026-11-01)")

      expect { connection.transaction(requires_new: true) { insert(valid_period: "[2026-10-31,)") } }
        .to raise_error(ActiveRecord::StatementInvalid, /item_prices_current_no_overlap/)
      expect { insert(valid_period: "[2026-11-01,)") }.not_to raise_error

      close(first)
      expect { insert(valid_period: "[,2026-11-01)", recorded_period: "[2026-10-05 00:00:00+00,)") }.not_to raise_error
    end

    it "別の品目なら、現在の行の有効期間が重なっても通す" do
      insert
      other = FactoryBot.create(:item, unit_price: nil)

      expect { FactoryBot.create(:item_price, item: other) }.not_to raise_error
    end
  end

  describe "書き換えを拒むトリガー" do
    let!(:id) { insert }

    def rejected(&) = expect { connection.transaction(requires_new: true, &) }.to raise_error(ActiveRecord::StatementInvalid, /item_prices/)

    it "現在の行の記録期間の上限だけを、始まりより後の時刻にする UPDATE を通す" do
      close(id)

      expect(connection.select_value("SELECT upper(recorded_period) FROM item_prices WHERE id = #{connection.quote(id)}"))
        .to eq(Time.utc(2026, 10, 5))
    end

    it "閉じる以外の UPDATE を拒む" do
      rejected { update(id, "unit_price = 90") }
      rejected { update(id, "valid_period = '[2026-10-01,)'") }
      rejected { update(id, "reason = '書き換え'") }
      rejected { update(id, "recorded_period = tstzrange('2026-09-01 00:00:00+00', '2026-10-05 00:00:00+00')") }
      rejected { close(id, "2026-10-01 00:00:00+00") }
      expect(connection.select_value("SELECT unit_price FROM item_prices WHERE id = #{connection.quote(id)}")).to eq(100)
    end

    it "閉じた行は、開き直すことも閉じ直すこともできない" do
      close(id)

      rejected { update(id, "recorded_period = tstzrange(lower(recorded_period), NULL)") }
      rejected { close(id, "2026-10-06 00:00:00+00") }
    end

    it "DELETE を拒む" do
      rejected { connection.execute("DELETE FROM item_prices WHERE id = #{connection.quote(id)}") }
      expect(connection.select_value("SELECT count(*) FROM item_prices")).to eq(1)
    end

    it "閉じた行と、記録期間の始まりの無い行は足せない" do
      rejected { insert(valid_period: "[2027-01-01,)", recorded_period: "[2026-10-01 00:00:00+00,2026-10-02 00:00:00+00)") }
      rejected { insert(valid_period: "[2027-01-01,)", recorded_period: "(,)") }
    end
  end

  it "空の有効期間と負の単価を拒む" do
    expect { connection.transaction(requires_new: true) { insert(valid_period: "empty") } }
      .to raise_error(ActiveRecord::StatementInvalid, /item_prices_valid_period_not_empty/)
    expect { connection.transaction(requires_new: true) { insert(unit_price: -1) } }
      .to raise_error(ActiveRecord::StatementInvalid, /item_prices_unit_price_non_negative/)
  end

  it "照合済みの受注明細は、priced_on を単価と一緒に持つ" do
    expect { connection.transaction(requires_new: true) { FactoryBot.create(:sales_order_line, :matched, priced_on: nil) } }
      .to raise_error(ActiveRecord::StatementInvalid, /sales_order_lines_matched_together/)
    expect { connection.transaction(requires_new: true) { FactoryBot.create(:sales_order_line, priced_on: Date.current) } }
      .to raise_error(ActiveRecord::StatementInvalid, /sales_order_lines_matched_together/)
  end
end
