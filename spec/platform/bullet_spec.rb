require "rails_helper"
require_relative "../support/events"
require_relative "../support/concurrency"

# 関連を 1 件ずつ読む N+1 が、テストの失敗まで届く（docs/architecture/graphql-schema.md「ページングと N+1」）。
# 公開 API・Dataloader のソース・/graphql への要求の 3 つの経路で、同じ N+1 が例外になることを確かめる。
# 包みの例外は example の後の around の中で起きて expect で捕まえられないので、自動の包みから外し、自分で包む
RSpec.describe "N+1 の検出", type: :request, bullet: false do
  let!(:supplier) { FactoryBot.create(:tenant) }
  let(:member) { Tenancy.with_tenant(supplier.id) { FactoryBot.create(:user) } }
  let(:actor) do
    Partnerships::Actor.new(user_id: member.id, tenant_id: supplier.id, name: member.name, email: member.email,
      role: member.role, partner_code: supplier.partner_code)
  end
  # Bullet は、1 回の読み込みで 1 件しか返らなかったレコードを N+1 の候補にしないので、親を 2 件作る
  let!(:order_ids) do
    Tenancy.with_tenant(supplier.id) { Array.new(2) { FactoryBot.create(:sales_order_line).sales_order_id } }
  end
  let(:query) { "{ supplier { salesOrders(first: 20) { nodes { id lines { id } } } } }" }

  before do
    # 受注のモデルはパッケージの外から参照できないので、同じ表を指す関連を spec の中で作る
    stub_const("BulletSpecOrder", Class.new(TenantRecord) do
      self.table_name = "sales_orders"
      has_many :lines, class_name: "BulletSpecOrderLine", foreign_key: :sales_order_id, inverse_of: false
    end)
    stub_const("BulletSpecOrderLine", Class.new(TenantRecord) { self.table_name = "sales_order_lines" })

    # 受注の明細の一括取得に、先読みせずに親ごとに関連を読む処理を足す
    allow(Sales::SalesOrders).to receive(:lines_for).and_wrap_original do |original, actor, ids|
      BulletSpecOrder.where(id: ids).each { |order| order.lines.to_a }
      original.call(actor, ids)
    end
  end

  def execute
    Tenancy.with_tenant(supplier.id) do
      Current.set(actor:) { FactoryOpsSchema.execute(query, context: { current_user: actor }) }
    end
  end

  it "公開 API を直接呼ぶと、例外になる" do
    expect do
      Bullet.profile { Tenancy.with_tenant(supplier.id) { Sales::SalesOrders.lines_for(actor, order_ids) } }
    end.to raise_error(Bullet::Notification::UnoptimizedQueryError, /BulletSpecOrder => \[:lines\]/)
  end

  it "Dataloader のソースの中で読んでも、例外になる" do
    expect { Bullet.profile { execute } }
      .to raise_error(Bullet::Notification::UnoptimizedQueryError, /BulletSpecOrder => \[:lines\]/)
  end

  it "/graphql への要求は、Bullet のミドルウェアが例外にする" do
    post "/session", params: { email: member.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)

    expect { post "/graphql", params: { query: }, as: :json }
      .to raise_error(Bullet::Notification::UnoptimizedQueryError, /BulletSpecOrder => \[:lines\]/)
  end

  describe "自動の包み（spec/support/bullet.rb）" do
    # 包みの例外は example の後で起きるので、中で別の example を走らせ、その結果を見る。
    # group.run は実行の絞り込み（-e など）を内側の example にも掛けるので、example を直接走らせる
    def run_inner_example(**metadata, &body)
      group = RSpec.describe("内側", **metadata) { it("関連を 1 件ずつ読む", &body) }
      RSpec.world.example_groups.delete(group)
      example = group.examples.sole
      example.run(group.new(example.inspect_output), RSpec::Core::NullReporter)
      @inner_metadata = example.metadata
      example.execution_result
    end

    def n_plus_one
      tenant_id = supplier.id
      ids = order_ids
      proc { Tenancy.with_tenant(tenant_id) { BulletSpecOrder.where(id: ids).each { |order| order.lines.to_a } } }
    end

    it "メタデータの無い example は、example の後に例外で落ちる" do
      result = run_inner_example(&n_plus_one)

      expect(result.status).to eq(:failed)
      expect(result.exception).to be_a(Bullet::Notification::UnoptimizedQueryError)
    end

    it "bullet: false の example は包まない" do
      expect(run_inner_example(bullet: false, &n_plus_one).status).to eq(:passed)
    end

    # 競合テストの後始末のガード（spec/support/concurrency.rb）も受けるので、内側の example は後始末を終える
    it ":concurrency の example は包まない" do
      read_lines = n_plus_one
      result = run_inner_example(concurrency: true) do
        read_lines.call
        delete_owned_rows([ SecureRandom.uuid ], [])
      end

      expect(result.status).to eq(:passed)
    end

    it "HTTP の要求を流す example（type: :request）は bullet: false を持ち、包まない" do
      expect(run_inner_example(type: :request, &n_plus_one).status).to eq(:passed)
      expect(@inner_metadata[:bullet]).to be(false)
    end

    # 要求ごとの検出は Bullet::Rack が要求の終わりに消すので、要求の後に流すイベントの受け手は、補助が自分で検出する
    it "HTTP の要求を流した後でイベントを流すと、受け手の中の N+1 で落ちる" do
      email = member.email
      read_lines = n_plus_one
      result = run_inner_example(type: :request) do
        post "/session", params: { email:, password: "password" }, as: :json
        allow(self).to receive(:enqueued_event_jobs).and_return([ instance_double(SolidQueue::Job, arguments: {}, finished!: true) ], [])
        allow(ActiveJob::Base).to receive(:execute) { read_lines.call }

        deliver_enqueued_events
      end

      expect(result.status).to eq(:failed)
      expect(result.exception).to be_a(Bullet::Notification::UnoptimizedQueryError)
    end

    # 検証の対象を factory の後に呼べば、factory で作ったレコードも N+1 の候補になる（spec/support/bullet.rb）。
    # 受注のモデルはパッケージの外から参照できないので、factory が返すレコードのクラスを使う
    it "factory で作った親を、factory の後に 1 件ずつ関連を読むと落ちる" do
      tenant_id = supplier.id
      result = run_inner_example do
        Tenancy.with_tenant(tenant_id) do
          lines = FactoryBot.create_list(:sales_order_line, 2)
          lines.first.sales_order.class.where(id: lines.map(&:sales_order_id)).each { |order| order.lines.to_a }
        end
      end

      expect(result.status).to eq(:failed)
      expect(result.exception.message).to match(/Sales::SalesOrder => \[:lines\]/)
    end
  end

  it "N+1 が無ければ、包んでも例外にならない" do
    allow(Sales::SalesOrders).to receive(:lines_for).and_call_original

    result = Bullet.profile { execute }

    expect(result["errors"]).to be_nil
    expect(result.dig("data", "supplier", "salesOrders", "nodes").map { _1["lines"].size }).to eq([ 1, 1 ])
  end
end

RSpec.describe BulletFactoryPause, bullet: false do
  it "factory で作ったレコードは、関連の factory で作ったものも含めて、N+1 の候補から外れない" do
    Bullet.profile do
      line = Tenancy.with_tenant(FactoryBot.create(:tenant).id) { FactoryBot.create(:sales_order_line) }

      expect(Bullet::Detector::NPlusOneQuery.impossible?(line)).to be(false)
      expect(Bullet::Detector::NPlusOneQuery.impossible?(line.sales_order)).to be(false)
      expect(Bullet.start?).to be(true)
    end
  end

  it "検出の外で factory を使っても、検出を始めない" do
    FactoryBot.create(:tenant)

    expect(Bullet.start?).to be_falsey
  end
end

RSpec.describe BulletDetection, bullet: false do
  let(:tenant) { FactoryBot.create(:tenant) }

  # Bullet.pause の間は Bullet.start? が偽になる。止めている間を検出の外と取り違えて Bullet.profile を始めると、
  # その end_request が外側の検出の状態を消し、再開した後の N+1 が見えない
  it "検出を止めている間に呼んでも、外側の検出の状態を消さず、再開した後の N+1 を検出する" do
    expect do
      Bullet.profile do
        Tenancy.with_tenant(tenant.id) do
          lines = FactoryBot.create_list(:sales_order_line, 2)
          Bullet.pause
          described_class.wrap { nil }
          Bullet.resume

          expect(Bullet.notification_collector).not_to be_nil
          lines.first.sales_order.class.where(id: lines.map(&:sales_order_id)).each { |order| order.lines.to_a }
        end
      end
    end.to raise_error(Bullet::Notification::UnoptimizedQueryError, /Sales::SalesOrder => \[:lines\]/)
  end

  it "検出の外で呼ぶと、ブロックの間だけ検出を始める" do
    expect(described_class.wrap { Bullet.start? }).to be(true)
    expect(Bullet.notification_collector).to be_nil
  end
end

RSpec.describe BulletSafelist, bullet: false do
  after { Bullet.delete_safelist(type: :n_plus_one_query, class_name: "BulletSpecOrder", association: :lines) }

  it "reason の無い行は、読み込みの時点で例外にする" do
    entry = { type: :n_plus_one_query, class_name: "BulletSpecOrder", association: :lines, reason: "" }

    expect { described_class.apply!([ entry ]) }.to raise_error(ArgumentError, /reason が無い/)
  end

  it "項目が 4 つにそろっていない行は、例外にする" do
    entry = { type: :n_plus_one_query, class_name: "BulletSpecOrder", association: :lines }

    expect { described_class.apply!([ entry ]) }.to raise_error(ArgumentError, /4 つに限る/)
  end

  it "reason のある行は、Bullet の許可リストに入る" do
    entry = { type: :n_plus_one_query, class_name: "BulletSpecOrder", association: :lines, reason: "受注は 1 件に決まる" }

    described_class.apply!([ entry ])

    expect(Bullet.get_safelist_associations(:n_plus_one_query, "BulletSpecOrder")).to include(:lines)
  end
end
