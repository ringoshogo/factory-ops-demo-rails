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

  # MatrixCrossRead.remove! を直に呼んでよい唯一の example。打ち切られた remove! が出す外す手順で外せることを確かめる。
  # describe のブロックの中の定数はファイルの最上位（Object）に定義されるので、ほかと重ならない名前にする
  MATRIX_CROSS_READ_DIRECT_REMOVE_EXAMPLE = "別の接続がテナントの表のロックを持つと、with_policies を抜けるときの remove! は待ちの上限で、ポリシーが残ったことと外す手順を出して落ち、手順で外すと次の add! が通る".freeze

  # 足し外しを流すスレッドの終わりを待つ上限の秒数。ポリシーの足し外しの待ちの上限（MatrixCrossRead::LOCK_TIMEOUT）より長くする
  def wait_seconds = ConcurrencyHelpers::WAIT_SECONDS

  # アプリのロールの、example のスレッドの接続とも所有ロールの接続とも別の接続で、最後のテナントの表のロックを取る。
  # 返した接続を閉じるまで、トランザクションを開いたままロックを持つ
  def lock_last_tenant_table
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    connection = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password],
      dbname: config[:database])
    connection.exec("BEGIN")
    connection.exec("LOCK TABLE #{connection.quote_ident(MatrixWorld.tenant_tables.last)} IN ACCESS SHARE MODE")
    connection
  end

  # ブロックを別のスレッドで流し、例外を拾って返す。ブロックが待ち続けても、example は join の上限で先へ進む
  def run_in_thread(&block)
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
      nil
    rescue StandardError => e
      e
    end
    thread.report_on_exception = false
    thread
  end

  # 打ち切れずに待っている所有ロールの接続を終わらせ、スレッドを待ってから所有ロールの接続を捨てる。
  # 待っていた DDL が、ロックが解けた後に開いたトランザクションのまま表のロックを持ち続けると、後ろの spec が止まる。
  # スレッドが接続を返す前に disconnect! を呼ぶと、使用中の接続を待って例外になりうるので、join の後に呼ぶ
  def stop_waiting_owner(thread)
    OwnerConnection.connection_pool.with_connection do |owner|
      owner.select_values(<<~SQL).each { owner.select_value("SELECT pg_terminate_backend(#{Integer(_1)})") }
        SELECT pid FROM pg_stat_activity
        WHERE datname = current_database() AND usename = current_user AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()
      SQL
    end
    thread&.join(wait_seconds)
    OwnerConnection.connection_pool.disconnect!
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

  # Prism の構文木から MatrixCrossRead.remove! の直の呼び出しを探す。コメントと文字列の中の語を呼び出しと取り違えない。
  # このファイルの MATRIX_CROSS_READ_DIRECT_REMOVE_EXAMPLE の example の中だけは外す。外す手順を確かめるには、手順そのものを流すしかない
  def direct_remove_call?(source, path)
    found = false
    visit = lambda do |node, exempt|
      if node.is_a?(Prism::CallNode)
        exempt ||= path == __FILE__ && node.name == :it && node.arguments&.arguments&.first.then do |name|
          name.is_a?(Prism::ConstantReadNode) && name.name == :MATRIX_CROSS_READ_DIRECT_REMOVE_EXAMPLE
        end
        if node.name == :remove! && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :MatrixCrossRead
          found ||= !exempt
        end
      end
      node.compact_child_nodes.each { visit.call(_1, exempt) }
    end
    visit.call(Prism.parse(source).value, false)
    found
  end

  # 外すのを足し終えたときに限る判定は MatrixCrossRead.share と with_policies にだけ置き、呼ぶ側に書き写させない。
  # 呼ぶ側が add! と remove! を対にして書くと、add! の失敗でも remove! が走る形を、補助を足すたびに書き直すことになる
  it "spec と補助は MatrixCrossRead.remove! を直に呼ばない" do
    calls = Dir[Rails.root.join("spec/**/*.rb")].reject { _1.end_with?("spec/support/matrix_cross_read.rb") }
      .select { direct_remove_call?(File.read(_1), _1) }

    expect(calls.map { _1.delete_prefix("#{Rails.root}/") }).to eq([])
    # 外すのは、このファイルの名指しの example の中だけで、同じファイルのほかの example と、ほかのファイルの同じ名前は外さない
    inside = "it MATRIX_CROSS_READ_DIRECT_REMOVE_EXAMPLE do\n  MatrixCrossRead.remove!\nend\n"
    outside = "it \"ほかの example\" do\n  MatrixCrossRead.remove!\nend\n"
    expect([ [ inside, __FILE__ ], [ outside, __FILE__ ], [ inside, "spec/other_spec.rb" ] ].map { direct_remove_call?(*_1) })
      .to eq([ false, true, true ])
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

  # 落ちた example の後に別の接続がテナントの表のロックを持ち続けると、ポリシーの足し外しの DDL が待ち続けて rspec が止まる。
  # 待ちに上限を置き、打ち切ったら待たせている接続を出す。状態とトランザクションの開始の時刻は、PostgreSQL が
  # 別のロールの接続の分を隠すので、待たせている接続と同じロールの接続から引く
  it "別の接続がテナントの表のロックを持つと、add! は待ちの上限で、待たせている接続の pid・ロール・状態・開始の時刻を出して落ち、ポリシーを残さない" do
    blocker = lock_last_tenant_table
    started = blocker.exec("SELECT now()::text").getvalue(0, 0)
    thread = run_in_thread { MatrixCrossRead.add! }

    expect(thread.join(wait_seconds)).not_to be_nil
    expect(thread.value&.message).to include(
      MatrixWorld.tenant_tables.last, "pid #{blocker.backend_pid}", ActiveRecord::Base.connection_db_config.configuration_hash[:username],
      "idle in transaction", started
    )
    expect(thread.value.cause).to be_a(ActiveRecord::LockWaitTimeout)
  ensure
    stop_waiting_owner(thread)
    blocker&.close
    expect(cross_policy_counts).to eq({})
  end

  # 世界と同じスレッドの接続がロックを持つ形。その接続は打ち切られたトランザクションの中にいることがあるので、状態を引かない
  it "add! を呼んだスレッドの接続がテナントの表のロックを持つと、その接続を「このスレッドの接続」と出して落ちる" do
    pid = nil
    thread = run_in_thread do |connection|
      connection.transaction do
        connection.execute("LOCK TABLE #{connection.quote_table_name(MatrixWorld.tenant_tables.last)} IN ACCESS SHARE MODE")
        pid = connection.raw_connection.backend_pid
        MatrixCrossRead.add!
      end
    end

    expect(thread.join(wait_seconds)).not_to be_nil
    role = ActiveRecord::Base.connection_db_config.configuration_hash[:username]
    expect(thread.value&.message).to include("pid #{pid}（#{role}、このスレッドの接続）")
  ensure
    stop_waiting_owner(thread)
    expect(cross_policy_counts).to eq({})
  end

  # 打ち切った後の診断が失敗しても、元の打ち切りの例外を隠さない。状態を引く問い合わせはセーブポイントの中で流し、
  # 失敗しても呼んだスレッドのトランザクションを壊さない。問い合わせを、SQL のエラーになる文に差し替えて確かめる
  it "ロックを持つ接続の状態を引く問い合わせが失敗しても、引けなかったと出し、打ち切りの例外を cause に残し、このスレッドのトランザクションを壊さない" do
    blocker = lock_last_tenant_table
    allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:select_one).and_wrap_original do |original, sql, *rest|
      original.call(sql.include?("FROM pg_stat_activity") ? "SELECT 1 / 0" : sql, *rest)
    end
    usable = nil
    thread = run_in_thread do |connection|
      connection.transaction do
        error = begin
          MatrixCrossRead.add!
          nil
        rescue StandardError => e
          e
        end
        usable = connection.select_value("SELECT 1")
        raise error if error
      end
    end

    expect(thread.join(wait_seconds)).not_to be_nil
    expect(thread.value&.message).to include("pid #{blocker.backend_pid}", "状態は引けなかった", "division by zero")
    expect(thread.value.cause).to be_a(ActiveRecord::LockWaitTimeout)
    expect(usable).to eq(1)
  ensure
    stop_waiting_owner(thread)
    blocker&.close
    expect(cross_policy_counts).to eq({})
  end

  it "ロックを持つ接続を pg_locks から引く問い合わせが失敗しても、引けなかったと出し、打ち切りの例外を cause に残す" do
    blocker = lock_last_tenant_table
    allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:select_rows).and_wrap_original do |original, sql, *rest|
      original.call(sql.include?("FROM pg_locks") ? "SELECT 1 / 0" : sql, *rest)
    end
    thread = run_in_thread { MatrixCrossRead.add! }

    expect(thread.join(wait_seconds)).not_to be_nil
    expect(thread.value&.message).to include("ロックを持つ接続：引けなかった", "division by zero")
    expect(thread.value.cause).to be_a(ActiveRecord::LockWaitTimeout)
  ensure
    stop_waiting_owner(thread)
    blocker&.close
    expect(cross_policy_counts).to eq({})
  end

  # 落ちた example の後始末（rspec-rails の fixture のトランザクションの巻き戻し）が飛ぶと、所有ロールの接続にトランザクションが残る。
  # その中で足すとコミットされず、全表のロックを持ったまま世界を作る接続を待たせ、lock_timeout では終わらない。
  # 確かめは add! で行う。remove! も同じ所有ロールの接続の取り方（with_owner_connection）を通る
  it "所有ロールの接続にトランザクションが残っていれば、add! はポリシーを足さずに、残ったことを出して落ちる" do
    owner = OwnerConnection.lease_connection
    owner.begin_transaction(joinable: false)

    expect { MatrixCrossRead.add! }.to raise_error(/所有ロールの接続にトランザクションが残っている/)
    expect(owner.select_value("SELECT count(*) FROM pg_policies WHERE policyname IN ('matrix_cross_read', 'matrix_cross_update')")).to eq(0)
  ensure
    owner&.rollback_transaction if owner&.transaction_open?
    OwnerConnection.connection_pool.release_connection
    expect(cross_policy_counts).to eq({})
  end

  # remove! が打ち切られるとポリシーが残り、次の実行の add! が「すでにある」で落ちるので、外す手順を出す。
  # ブロックを抜けるのは別のスレッドにする。同じスレッドがロックを握ったまま抜けると、remove! の待ちの上限を外したときに
  # ロックを解く者がいないので、example が落ちずに rspec ごと止まる。
  # 手順で外せることを確かめるために、この example だけは MatrixCrossRead.remove! を直に呼ぶ
  it MATRIX_CROSS_READ_DIRECT_REMOVE_EXAMPLE do
    entered = Queue.new
    leave = Queue.new
    thread = run_in_thread do
      MatrixCrossRead.with_policies do
        entered << true
        leave.pop(timeout: wait_seconds)
      end
    end
    added = entered.pop(timeout: wait_seconds)
    expect(added).to be(true)
    blocker = lock_last_tenant_table
    leave << true

    expect(thread.join(wait_seconds)).not_to be_nil
    database = ActiveRecord::Base.connection_db_config.database
    command = [ "RAILS_ENV=test", ("TEST_DATABASE=#{database}" unless database == "factory_ops_demo_rails_test"), "bin/rails runner",
                "spec/support/matrix_world", "spec/support/matrix_cross_read", "MatrixCrossRead.remove!" ].compact
    expect(thread.value&.message).to include("ポリシーが残った", "pid #{blocker.backend_pid}", *command)
    tables = MatrixWorld.tenant_tables.size
    expect(cross_policy_counts).to eq("matrix_cross_read" => tables, "matrix_cross_update" => tables)

    blocker.close
    blocker = nil
    MatrixCrossRead.remove!
    expect { MatrixCrossRead.with_policies { nil } }.not_to raise_error
    expect(cross_policy_counts).to eq({})
  ensure
    leave&.push(true)
    stop_waiting_owner(thread)
    blocker&.close
    # 足したのがこの example のときだけ外す。足すのに失敗したなら、先にあったのは別の実行のポリシーである
    MatrixCrossRead.remove! if added
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
