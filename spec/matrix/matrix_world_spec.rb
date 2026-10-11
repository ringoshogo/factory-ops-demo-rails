require "rails_helper"
require_relative "../support/matrix_world"

# 行列の世界をファイルごとに作る補助が、example で足した行とテナントの設定を次の example に渡さず、
# ファイルの終わりに世界を残さず、世界のトランザクションが途中で閉じたことを失敗にする
# （docs/guides/testing.md「行列テストとの分担」）。補助が誤ると、行列テストは前の example が汚した世界の上で通る
RSpec.describe MatrixWorld do
  # 世界を包むトランザクションを、この spec の example ごとのトランザクションの外で開く
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.lease_connection }
  let(:pool) { ActiveRecord::Base.connection_pool }

  # example が失敗して世界を閉じ損ねても、接続の固定を残して後の spec を巻き込まない
  after do
    pool.unpin_connection! while pool.instance_variable_get(:@pinned_connection)
  end

  def count_tenants(ids)
    connection.select_value("SELECT count(*) FROM tenants WHERE id IN (#{ids.map { connection.quote(_1) }.join(', ')})")
  end

  def tenant_setting = connection.select_value("SELECT current_setting('app.tenant_id', true)")

  # 行列の spec と同じ形の内側の example group を走らせ、example の結果を返す。
  # 実行の絞り込み（-e など）と --order rand を内側に掛けず、書いた順に走らせる
  def run_inner_group(&body)
    group = RSpec.describe("内側の行列", order: :defined) do
      MatrixWorld.share_per_file(self)
      instance_exec(&body)
    end
    RSpec.world.example_groups.delete(group)
    RSpec.world.filtered_examples[group] = group.examples
    group.run(RSpec::Core::NullReporter)
    group.examples.map { [ _1.execution_result.status, _1.execution_result.exception&.message ] }
  end

  it "example で足した行とテナントの設定は次の example に残らず、ファイルの終わりに世界が残らない" do
    seen = {}
    results = run_inner_group do
      it "行を足し、セッションのテナントを設定する" do
        seen[:tenants] = world.tenants.values
        seen[:item] = world.as(:supplier) { FactoryBot.create(:item).id }
        connection = ActiveRecord::Base.lease_connection
        connection.select_value("SELECT set_config('app.tenant_id', $1, false)", "Spec", [ world.tenants[:supplier] ])
        expect(world.as(:supplier) { connection.select_value("SELECT count(*) FROM items WHERE id = $1", "Spec", [ seen[:item] ]) }).to eq(1)
      end

      it "前の example の行と設定は無く、世界の行はある" do
        connection = ActiveRecord::Base.lease_connection
        expect(connection.select_value("SELECT current_setting('app.tenant_id', true)")).to be_blank
        world.as(:supplier) do
          expect(connection.select_value("SELECT count(*) FROM items WHERE id = $1", "Spec", [ seen[:item] ])).to eq(0)
          expect(connection.select_value("SELECT count(*) FROM items WHERE id = $1", "Spec", [ world.row("items", :supplier).id ])).to eq(1)
        end
      end
    end

    expect(results).to eq([ [ :passed, nil ], [ :passed, nil ] ])
    expect(seen[:tenants].size).to eq(MatrixWorld::PERSONAS.size)
    expect(count_tenants(seen[:tenants])).to eq(0)
    expect(connection.transaction_open?).to be(false)
  end

  it "世界のオブジェクトの属性を書き換えると例外になる" do
    world = MatrixWorld.open
    user = world.users[:supplier]

    expect(user.email).to be_present
    expect { user.name = "書き換え" }.to raise_error(FrozenError)
    expect { world.tenants[:stranger] = "書き換え" }.to raise_error(FrozenError)
  ensure
    MatrixWorld.close if world
  end

  it "世界のトランザクションがファイルの終わりより前に閉じると、閉じるときに失敗し、接続の固定は外れる" do
    world = MatrixWorld.open
    tenants = world.tenants.values
    expect(count_tenants(tenants)).to eq(tenants.size)

    connection.rollback_transaction

    expect { MatrixWorld.close }.to raise_error(/ファイルの終わりより前に閉じた/)
    expect(connection.transaction_open?).to be(false)
    expect(count_tenants(tenants)).to eq(0)
  end

  it "世界を作った後にテナントの設定が残っていれば、作った行と接続の固定を残さずに失敗する" do
    created = []
    allow(MatrixWorld).to receive(:new).and_wrap_original do |original|
      original.call.tap do |world|
        created.concat(world.tenants.values)
        connection.select_value("SELECT set_config('app.tenant_id', $1, false)", "Spec", [ world.tenants[:supplier] ])
      end
    end

    expect { MatrixWorld.open }.to raise_error(/テナントの設定が残っている/)
    expect(created.size).to eq(MatrixWorld::PERSONAS.size)
    expect(count_tenants(created)).to eq(0)
    expect(connection.transaction_open?).to be(false)
    expect(tenant_setting).to be_blank
  end
end
