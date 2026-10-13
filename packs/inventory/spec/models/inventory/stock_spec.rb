require "rails_helper"
require "prism"

# 在庫を変える唯一の入口 Stock#move! と、有効在庫が負にならない CHECK 制約（docs/architecture/data-model.md「在庫（`inventory`）」）
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

  it "安全在庫の変更は安全在庫だけを書き、数量を一緒に書き換えようとすると拒否する" do
    stock.change_safety_stock!(4)
    expect(stock.reload.slice(:on_hand, :safety_stock)).to eq("on_hand" => 10, "safety_stock" => 4)

    stock.on_hand = 99
    expect { stock.change_safety_stock!(5) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(stock.reload.slice(:on_hand, :safety_stock)).to eq("on_hand" => 10, "safety_stock" => 4)
  end

  # readonly? はクラス単位の一括の書き込みを止めない。在庫の行は在庫のパッケージの外から参照できない（packwerk の
  # enforce_privacy）ので、パッケージの中のコードが一括の書き込みを呼ばないことで、move! を唯一の入口に保つ。
  # 例外は、数量 0 の行を足すだけの lock_for の insert_all と、在庫の行ではなく品目の写しを書く ItemLabels.put の upsert_all である。呼び出しは Prism の構文木から拾い、
  # コメントと文字列の中の語を呼び出しと取り違えない。SQL を直接流す書き込みは、メソッドの名前で見分けられないので対象にしない
  describe "一括の書き込み" do
    let(:bulk_writes) do
      %i[update_all update_counters increment_counter decrement_counter upsert upsert_all insert insert! insert_all insert_all!]
    end

    # source の中で一括の書き込みを呼ぶ箇所を、[囲むメソッドの名前, 呼ぶメソッドの名前] の配列で返す
    def bulk_write_calls(source)
      calls = []
      visit = lambda do |node, method_name|
        method_name = node.name if node.is_a?(Prism::DefNode)
        calls << [ method_name, node.name ] if node.is_a?(Prism::CallNode) && bulk_writes.include?(node.name)
        node.compact_child_nodes.each { visit.call(_1, method_name) }
      end
      visit.call(Prism.parse(source).value, nil)
      calls
    end

    it "在庫のパッケージのコードは、lock_for の insert_all と品目の写しの upsert_all のほかに一括の書き込みを呼ばない" do
      root = File.expand_path("../../../app", __dir__)
      found = Dir.glob("#{root}/**/*.rb").sort.flat_map do |path|
        bulk_write_calls(File.read(path)).map { [ path.delete_prefix("#{root}/"), *_1 ] }
      end

      expect(found).to eq([ [ "models/inventory/stock.rb", :lock_for, :insert_all ], [ "public/inventory/item_labels.rb", :put, :upsert_all ] ])
    end

    it "検査は、文字列の補間を引数に含む呼び出しを拾い、コメントの中の語を拾わない" do
      source = <<~'RUBY'
        def reset(item_id)
          Stock.where(item_id: "#{item_id}").update_all(on_hand: 0) # upsert_all
        end
        # Stock.insert_all([])
      RUBY

      expect(bulk_write_calls(source)).to eq([ [ :reset, :update_all ] ])
    end
  end

  it "書いた移動履歴は変えられない" do
    stock.move!("inbound", 1)
    movement = Inventory::StockMovement.last

    expect { movement.update!(quantity: 2) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { movement.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
