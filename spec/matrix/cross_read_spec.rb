require "rails_helper"
require_relative "../support/cross_read"

# 共有の文脈「RLS の SELECT と UPDATE を開く」が、グループの間だけ 2 つのポリシーを足し、グループの後に外し、
# 足すのに失敗したときは、先にあったポリシーを外さない（docs/guides/testing.md「行列テストとの分担」）。
# 誤ると、同じテストの DB で行列を流すほかの実行の 2 回目が空振りする
RSpec.describe "共有の文脈「RLS の SELECT と UPDATE を開く」" do
  # ポリシーの足し外しは所有ロールの接続で表のロックを取るので、example ごとのトランザクションの外で走らせる
  self.use_transactional_tests = false

  # 足した 2 つのポリシーの形ごとの表の数。名前・操作・USING・WITH CHECK が同じ行をまとめる
  def cross_policy_shapes
    ActiveRecord::Base.lease_connection.select_rows(<<~SQL)
      SELECT policyname::text, permissive, cmd, qual, with_check, count(*) FROM pg_policies
      WHERE schemaname = 'public' AND policyname IN ('matrix_cross_read', 'matrix_cross_update')
      GROUP BY 1, 2, 3, 4, 5 ORDER BY 1
    SQL
  end

# 2 つのポリシーの名前ごとの表の数。形が違っても同じ名前なら数える
def cross_policy_counts
  ActiveRecord::Base.lease_connection.select_rows(<<~SQL).to_h
    SELECT policyname::text, count(*) FROM pg_policies
    WHERE schemaname = 'public' AND policyname IN ('matrix_cross_read', 'matrix_cross_update') GROUP BY 1
  SQL
end

  # 文脈を使う内側の example group を走らせ、example の結果を返す。実行の絞り込みと --order rand を内側に掛けない
  def run_inner_group(&body)
    group = RSpec.describe("内側の文脈", order: :defined) do
      include_context "RLS の SELECT と UPDATE を開く"
      instance_exec(&body)
    end
    RSpec.world.example_groups.delete(group)
    RSpec.world.filtered_examples[group] = group.examples
    group.run(RSpec::Core::NullReporter)
    group.examples.map { [ _1.execution_result.status, _1.execution_result.exception&.message ] }
  end

  # UPDATE のポリシーは WITH CHECK (false) を明示する。書き落とすと PostgreSQL は USING を WITH CHECK に使い、
  # 設定が on の間は他社の名義の行を書けてしまう。許可のポリシーの WITH CHECK は OR でつながるので、
  # false なら書いた後の行は owner_write の WITH CHECK（自社の行）だけで判定される
  it "グループの間だけ、全表に SELECT と UPDATE に限る 2 つのポリシーを足し、UPDATE の WITH CHECK は false にし、終わったら外す" do
    seen = nil
    shapes = method(:cross_policy_shapes)
    results = run_inner_group { it("数える") { seen = shapes.call } }

    opened = "(current_setting('app.matrix_cross_read'::text, true) = 'on'::text)"
    tables = MatrixWorld.tenant_tables.size
    expect(results).to eq([ [ :passed, nil ] ])
    expect(seen).to eq([
      [ "matrix_cross_read", "PERMISSIVE", "SELECT", opened, nil, tables ],
      [ "matrix_cross_update", "PERMISSIVE", "UPDATE", opened, "false", tables ]
    ])
    expect(cross_policy_shapes).to eq([])
  end

  # 外すのを足し終えたときに限る判定は MatrixCrossRead.share と with_policies にだけ置き、呼ぶ側に書き写させない。
  # 呼ぶ側が add! と remove! を対にして書くと、add! の失敗でも remove! が走る形を、補助を足すたびに書き直すことになる。
  # 呼び出しは Prism の構文木から拾い、コメントと文字列の中の語を呼び出しと取り違えない
  it "spec と補助は MatrixCrossRead.remove! を直に呼ばない" do
    calls = Dir[Rails.root.join("spec/**/*.rb")].reject { _1.end_with?("spec/support/matrix_cross_read.rb") }.select do |path|
      found = false
      visit = lambda do |node|
        if node.is_a?(Prism::CallNode) && node.name == :remove! && node.receiver.is_a?(Prism::ConstantReadNode) &&
            node.receiver.name == :MatrixCrossRead
          found = true
        end
        node.compact_child_nodes.each { visit.call(_1) }
      end
      visit.call(Prism.parse_file(path).value)
      found
    end

    expect(calls.map { _1.delete_prefix("#{Rails.root}/") }).to eq([])
  end

  it "with_policies は、足すのに失敗したら、先にあったポリシーを外さずに送出する" do
    tables = MatrixWorld.tenant_tables.size
    MatrixCrossRead.with_policies do
      expect { MatrixCrossRead.with_policies { nil } }.to raise_error(/matrix_cross_read か matrix_cross_update のポリシーがすでにある/)
      expect(cross_policy_counts).to eq("matrix_cross_read" => tables, "matrix_cross_update" => tables)
    end
    expect(cross_policy_counts).to eq({})
  end

  it "同じ名前のポリシーがすでにあれば、足さずに失敗し、あったポリシーを外さない" do
    MatrixCrossRead.with_policies do
      results = run_inner_group { it("走らない") { nil } }

      expect(results.first.last).to include("matrix_cross_read か matrix_cross_update のポリシーがすでにある")
      tables = MatrixWorld.tenant_tables.size
      expect(cross_policy_counts).to eq("matrix_cross_read" => tables, "matrix_cross_update" => tables)
    end
  end

  # 足すのは 1 つのトランザクションなので、最後に足す表の UPDATE のポリシーだけが重なって失敗しても、前に足しかけた
  # ポリシーは残らない。先にあったポリシーは、どの行も対象にしない形（USING (false)）で置き、example の後で外す
  it "最後の表の UPDATE のポリシーだけが先にあれば、足さずに失敗し、足しかけたポリシーを残さず、あったポリシーを外さない" do
    owner = OwnerConnection.lease_connection
    last = owner.quote_table_name(MatrixWorld.tenant_tables.last)
    owner.execute("CREATE POLICY matrix_cross_update ON #{last} FOR UPDATE USING (false)")
    begin
      expect { MatrixCrossRead.with_policies { nil } }.to raise_error(/matrix_cross_read か matrix_cross_update のポリシーがすでにある/)
      expect(cross_policy_counts).to eq("matrix_cross_update" => 1)
    ensure
      owner.execute("DROP POLICY IF EXISTS matrix_cross_update ON #{last}")
    end
  end
end
