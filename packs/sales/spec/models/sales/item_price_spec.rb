require "rails_helper"

# 単価の行の端の読み方と、現在の行を閉じる操作（docs/adr/006 決定 3）
RSpec.describe Sales::ItemPrice do
  include ActiveSupport::Testing::TimeHelpers

  let(:supplier) { FactoryBot.create(:tenant) }

  around { |example| TenantExample.run(example, supplier.id) }

  it "上限の無い有効期間の端を空で読み、有効期間に含まれる日だけを含む" do
    open_ended = FactoryBot.create(:item_price)
    bounded = FactoryBot.create(:item_price, valid_period: Date.new(2026, 10, 1)...Date.new(2026, 11, 1))

    expect([ open_ended.valid_from, open_ended.valid_to ]).to eq([ nil, nil ])
    expect([ bounded.valid_from, bounded.valid_to ]).to eq([ Date.new(2026, 10, 1), Date.new(2026, 11, 1) ])
    expect([ Date.new(2026, 9, 30), Date.new(2026, 10, 1), Date.new(2026, 10, 31), Date.new(2026, 11, 1) ].map { bounded.covers?(_1) })
      .to eq([ false, true, true, false ])
  end

  it "閉じた行をもう一度閉じると、書き換えずに例外にする" do
    row = travel_to(Time.zone.local(2026, 10, 1)) { FactoryBot.create(:item_price) }
    row.close!(Time.zone.local(2026, 10, 2))

    expect { row.close!(Time.zone.local(2026, 10, 3)) }.to raise_error(ActiveRecord::StaleObjectError)
    expect(row.reload.recorded_to).to eq(Time.zone.local(2026, 10, 2))
  end
end
