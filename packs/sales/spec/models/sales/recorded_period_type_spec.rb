require "rails_helper"

# 販売単価の記録期間の型。終わりの無い範囲は終わりを空で書き、upper_inf が真の現在の行にする（docs/adr/006 決定 3）。
# activerecord 8.1 は、始まりが Time の終わりの無い範囲の終わりを infinity で書くので、この型が無いと現在の行に数えられない
RSpec.describe Sales::RecordedPeriodType do
  subject(:type) { described_class.new }

  let(:at) { Time.utc(2026, 10, 11, 16, 0, 0.5) }

  it "終わりの無い範囲を、UTC の始まりと空の終わりで書く。日本時間の時刻でも同じになる" do
    expect(type.serialize(at...)).to eq("[2026-10-11T16:00:00.500000Z,)")
    expect(type.serialize(at.in_time_zone("Asia/Tokyo")...)).to eq("[2026-10-11T16:00:00.500000Z,)")
  end

  it "終わりのある範囲と、範囲でない値は、元の型の書き方のままにする" do
    closed = at...(at + 60)

    expect(type.serialize(closed)).to eq(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Range
      .new(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::TimestampWithTimeZone.new, :tstzrange).serialize(closed))
    expect(type.serialize(nil)).to be_nil
  end

  it "書いた終わりの無い行は、DB で upper_inf が真になり、読み直すと終わりが空になる" do
    Tenancy.with_tenant(FactoryBot.create(:tenant).id) do
      row = FactoryBot.create(:item_price, recorded_period: at...)
      connection = ActiveRecord::Base.lease_connection

      expect(connection.select_value("SELECT upper_inf(recorded_period) FROM item_prices WHERE id = $1", "SQL", [ row.id ])).to be(true)
      expect(Sales::ItemPrice.find(row.id).recorded_period.end).to be_nil
    end
  end
end
