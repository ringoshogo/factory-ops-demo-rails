require "rails_helper"

# 在庫を変える唯一の入口 Stock#move! と、有効在庫が負にならない CHECK 制約（docs/architecture/data-model.md「在庫」）
RSpec.describe Inventory::Stock do
  let(:tenant) { FactoryBot.create(:tenant) }

  around { |example| Tenancy.with_tenant(tenant.id) { example.run } }

  let(:stock) { FactoryBot.create(:stock, on_hand: 10) }

  it "移動の種類ごとに現在庫と引当を増減し、移動履歴を 1 行ずつ足す" do
    allocation = FactoryBot.create(:allocation, item_id: stock.item_id, quantity: 4)
    expect {
      stock.move!("inbound", 5, reason: "入荷")
      stock.move!("outbound", 2)
      stock.move!("allocate", 4, allocation:)
      stock.move!("deallocate", 1, allocation:)
      stock.move!("ship", 3, allocation:)
    }.to change(Inventory::StockMovement, :count).by(5)

    expect(stock.reload.slice(:on_hand, :allocated)).to eq("on_hand" => 10, "allocated" => 0)
    expect(Inventory::StockMovement.where(item_id: stock.item_id).order(:id).pluck(:type, :quantity))
      .to eq([ [ "inbound", 5 ], [ "outbound", 2 ], [ "allocate", 4 ], [ "deallocate", 1 ], [ "ship", 3 ] ])
  end

  it "有効在庫を超える引当は DB の CHECK 制約が拒否し、移動履歴も残らない" do
    allocation = FactoryBot.create(:allocation, item_id: stock.item_id, quantity: 11)

    expect {
      Inventory::Stock.transaction(requires_new: true) { stock.move!("allocate", 11, allocation:) }
    }.to raise_error(ActiveRecord::StatementInvalid, /stocks_available_non_negative/)
    expect(Inventory::StockMovement.where(item_id: stock.item_id)).to be_empty
  end

  it "現在庫を引当より少なくする出庫も CHECK 制約が拒否する" do
    allocation = FactoryBot.create(:allocation, item_id: stock.item_id, quantity: 8)
    stock.move!("allocate", 8, allocation:)

    expect {
      Inventory::Stock.transaction(requires_new: true) { stock.move!("outbound", 3) }
    }.to raise_error(ActiveRecord::StatementInvalid, /stocks_available_non_negative/)
  end

  it "move! を通らない数量の書き換えは拒否する" do
    expect { stock.update!(on_hand: 99) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { stock.update_columns(on_hand: 99) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(stock.reload.on_hand).to eq(10)
  end

  # readonly? はクラス単位の一括の書き込みを止めない。在庫の行は在庫のパッケージの外から参照できない（packwerk の
  # enforce_privacy）ので、パッケージの中のコードが一括の書き込みを使わないことで、move! を唯一の入口に保つ。
  # 例外は、数量 0 の行を足すだけの lock_for の insert_all である
  it "在庫のパッケージのコードは、move! を通らない一括の書き込みを使わない" do
    bulk_writes = /\b(?:update_all|update_counters|(?:increment|decrement)_counter|upsert(?:_all)?|insert(?:_all)?!?)\b/
    root = File.expand_path("../../../app", __dir__)
    found = Dir.glob("#{root}/**/*.rb").flat_map do |path|
      File.readlines(path).filter_map.with_index(1) do |line, lineno|
        "#{path.delete_prefix("#{root}/")}:#{lineno}: #{line[bulk_writes]}" if line.sub(/#.*/, "").match?(bulk_writes)
      end
    end

    expect(found.map { _1.sub(/:\d+:/, ":") }).to eq([ "models/inventory/stock.rb: insert_all" ])
  end

  it "書いた移動履歴は変えられない" do
    stock.move!("inbound", 1)
    movement = Inventory::StockMovement.last

    expect { movement.update!(quantity: 2) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { movement.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
