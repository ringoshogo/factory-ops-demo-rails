require_relative "owner_connection"

# 入口の行列の 2 回目と、操作者のいない入口の公開 API の単体のために、テナントの表ごとに、設定 app.matrix_cross_read が
# on のときだけ全行を読ませる SELECT のポリシーと、全行を UPDATE の対象に入れる UPDATE のポリシーを足し外す
# （docs/guides/testing.md「行列テストとの分担」）。RLS が他社の行を隠すと、公開 API の scope や所有の条件を外しても
# 結果が変わらないので、RLS を開いた結果と比べて抜けを捕まえる。UPDATE と SELECT ... FOR UPDATE は、SELECT のポリシーに加えて
# UPDATE のポリシーの USING を満たす行しか対象にしないので、SELECT だけを開いても所有の条件の抜けが見えない。
# UPDATE のポリシーは書いた後の行を何も通さない（WITH CHECK (false)）ので、他社の行を引いた書き込みは owner_write の
# WITH CHECK に当たって例外になる。ただし設定が on の間は、他社の行を自社の名義に書き換える UPDATE が通るので、
# 単体は他社の行が変わらないことも確かめる。
# アプリのロールは app.* の設定を自由に変えられるので、このポリシーが本番に載れば、全テナントの行を読み、他社の行を自社の名義に書き換える抜け道になる。
# そのため SQL はここにだけ置き、lib/tenant_table.rb とマイグレーションには置かない。
# structure.sql に混ざれば bin/check-structure が、消し忘れれば spec/db/tenant_enforcement_spec.rb が落とす
module MatrixCrossRead
  POLICY = "matrix_cross_read".freeze
  UPDATE_POLICY = "matrix_cross_update".freeze
  SETTING = "app.matrix_cross_read".freeze

  # ポリシーの足し外しが表のロックを待つ上限。正常な全件の実行では、add! も remove! も全表で 0.05 秒の内に終わる。
  # 上限が無いと、落ちた example の後に別の接続が表のロックを持ち続けたときに、DDL が待ち続けて rspec が止まる
  LOCK_TIMEOUT = "2s".freeze

  # 既定のテストの DB の名前（config/database.yml）。これと違う DB なら、外す手順に TEST_DATABASE を書く
  DEFAULT_TEST_DATABASE = "factory_ops_demo_rails_test".freeze

  # 所有ロールの接続で、全表の 2 つのポリシーを 1 つのトランザクションで足す。途中で失敗すると全部が巻き戻り、足した分は残らない。
  # 世界を開く前に呼ぶ。ポリシーの足し外しは表のロックを取るので、全表に書いた世界の外側のトランザクションが開いている間は、
  # それが閉じるまで待ち、LOCK_TIMEOUT で打ち切って、ロックを持つ接続を出して失敗する。
  # 同じ名前のポリシーがあれば、別の実行が同じテストの DB で行列を流しているか、途中で止めた実行が残したので、外さずに失敗する
  def self.add!
    with_owner_connection do |connection|
      each_table_within_lock_timeout(connection, "add!") do |table|
        # WITH CHECK を書き落とすと PostgreSQL は USING を WITH CHECK に使い、設定が on の間は他社の名義の行を書ける。
        # 許可のポリシーの WITH CHECK は OR でつながるので、false なら書いた後の行は owner_write の WITH CHECK だけで判定される
        connection.execute(<<~SQL)
          CREATE POLICY #{POLICY} ON #{connection.quote_table_name(table)} FOR SELECT
            USING (current_setting('#{SETTING}', true) = 'on');
          CREATE POLICY #{UPDATE_POLICY} ON #{connection.quote_table_name(table)} FOR UPDATE
            USING (current_setting('#{SETTING}', true) = 'on') WITH CHECK (false);
        SQL
      end
    end
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::DuplicateObject)

    raise "#{POLICY} か #{UPDATE_POLICY} のポリシーがすでにある。同じテストの DB で行列を流しているほかの実行が無ければ、" \
      "途中で止めた実行が残したものなので、#{remove_command} で外す（docs/guides/testing.md「行列テストとの分担」）"
  end

  # グループの前にポリシーを足し、後に外す。外すのは、このグループが足し終えたときだけにする。
  # rspec は before(:context) が失敗しても after(:context) を走らせ（rspec-core 3.13 の lib/rspec/core/example_group.rb の
  # ExampleGroup.run が ensure で run_after_context_hooks を呼ぶ）、足すのに失敗したときに外すと、同じ DB に先に足した
  # 別の実行のポリシーを消すからである。after(:context) は登録の逆の順に走るので、ほかのフックより先に呼べば、
  # ほかのフックが開いた世界を閉じた後に外れる
  def self.share(group)
    group.before(:context) do
      MatrixCrossRead.add!
      @matrix_cross_read_added = true
    end
    group.after(:context) { MatrixCrossRead.remove! if @matrix_cross_read_added }
  end

  # ブロックの間だけポリシーを足す。足すのに失敗したときは外さない（share と同じ理由）
  def self.with_policies
    add!
    begin
      yield
    ensure
      remove!
    end
  end

  # 足していない表があっても失敗しない。spec と補助は直に呼ばず、share か with_policies を通す。
  # 途中で止めた実行が残したポリシーを手で外すときにだけ、直に呼ぶ。
  # ロックの待ちを打ち切るとトランザクションごと巻き戻り、ポリシーは残るので、残ったことと外す手順を出す
  def self.remove!
    with_owner_connection do |connection|
      left = "#{POLICY} と #{UPDATE_POLICY} のポリシーが残った。ロックが解けた後に、#{remove_command} で外す"
      each_table_within_lock_timeout(connection, "remove!", left) do |table|
        [ POLICY, UPDATE_POLICY ].each do |policy|
          connection.execute("DROP POLICY IF EXISTS #{policy} ON #{connection.quote_table_name(table)}")
        end
      end
    end
  end

  # example のトランザクションの中だけで RLS の SELECT と UPDATE を開く。example のセーブポイントを巻き戻すと設定も戻る。
  # ロールや DB の既定に書くと、example の外とほかの spec の接続にも開く
  def self.on!
    ActiveRecord::Base.lease_connection.select_value("SELECT set_config('#{SETTING}', 'on', true)")
  end

  # 接続先の名前がテストの DB でなければ、何もせずに失敗する。開発の DB に足すと、そこでアプリのロールが全行を読める
  def self.with_owner_connection
    OwnerConnection.connection_pool.with_connection do |connection|
      database = connection.current_database
      unless Rails.env.test? && database.match?(/_test(_|\z)/)
        raise "テストの DB ではない #{database}（#{Rails.env}）に、全行を読ませるポリシーを足そうとした"
      end

      # 落ちた example の後始末（rspec-rails の fixture のトランザクションの巻き戻し）が飛ぶと、所有ロールの接続に
      # トランザクションが残る。その中で足し外ししてもコミットされず、全表のロックを持ったまま、世界を作るアプリのロールの
      # 接続を待たせる。待つのはアプリのロールの側なので LOCK_TIMEOUT では終わらず、rspec が止まる
      if connection.transaction_open?
        raise "所有ロールの接続にトランザクションが残っている（#{connection.open_transactions} 段）。前の example の後始末が" \
          "トランザクションを巻き戻せなかったので、ポリシーを足し外ししない。先に落ちた example とその around のフックを見る。" \
          "example をテナントで包む around は TenantExample.run を通す（docs/guides/testing.md「層への配分」）"
      end

      yield connection
    end
  end
  private_class_method :with_owner_connection

  # 1 つのトランザクションで LOCK_TIMEOUT を置き、表ごとにブロックを流す。ロックの待ちを打ち切ったら、巻き戻した後に、
  # 打ち切った表のロックを持つ接続を引いて失敗する。元の例外は cause に残る
  def self.each_table_within_lock_timeout(connection, action, left = nil)
    current = nil
    connection.transaction do
      connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
      MatrixWorld.tenant_tables.each do |table|
        current = table
        yield table
      end
    end
  rescue ActiveRecord::LockWaitTimeout
    raise [ "MatrixCrossRead.#{action} が #{current} のロックを #{LOCK_TIMEOUT} 待って打ち切った。" \
            "ロックを持つ接続：#{lock_holders(connection, current)}", left ].compact.join("。")
  end
  private_class_method :each_table_within_lock_timeout

  # 表の取得済みのロックを持つ、自分でない接続を並べる。打ち切られたトランザクションの中では問い合わせを流せず、
  # 巻き戻した後は待ちが無いので pg_blocking_pids も空になるため、表の pg_locks から引く。
  # PostgreSQL は別のロールの接続の状態と開始の時刻を pg_stat_activity で隠し（PostgreSQL 18 の文書の「Viewing Statistics」）、
  # 所有ロールは pg_read_all_stats を持たないので、状態はその接続と同じロールの接続から引き、どちらの権限も広げない。
  # 引けなかったら引けなかったと書き、元の lock_timeout の例外を隠さない
  def self.lock_holders(owner, table)
    holders = owner.select_rows(<<~SQL)
      SELECT DISTINCT l.pid, a.usename::text FROM pg_locks l LEFT JOIN pg_stat_activity a ON a.pid = l.pid
      WHERE l.locktype = 'relation' AND l.granted AND l.pid <> pg_backend_pid()
        AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND l.relation = #{owner.quote(owner.quote_table_name(table))}::regclass
      ORDER BY 1
    SQL
    return "見つからなかった（打ち切った後に解けた）" if holders.empty?

    app_role = ActiveRecord::Base.connection_db_config.configuration_hash[:username]
    owner_role = owner.pool.db_config.configuration_hash[:username]
    holders.map do |pid, role|
      detail =
        case role
        when app_role
          ActiveRecord::Base.connection_pool.with_connection do |app|
            # 世界と同じスレッドの接続は、打ち切られたトランザクションの中にいることがあり、問い合わせを流せない
            app.raw_connection.backend_pid == pid ? "このスレッドの接続" : activity(app, pid)
          end
        when owner_role then activity(owner, pid)
        else "状態は引けなかった（引ける接続の無いロール）"
        end
      "pid #{pid}（#{role || 'ロール不明'}、#{detail}）"
    end.join("、")
  rescue StandardError => e
    "引けなかった（#{e.class}: #{e.message.lines.first&.strip}）"
  end
  private_class_method :lock_holders

  # 同じロールの接続から、pid の状態・トランザクションの開始の時刻・最後の問い合わせを引く。
  # 開いたトランザクションを失敗で巻き戻さないよう、セーブポイントの中で流す
  def self.activity(connection, pid)
    row = connection.transaction(requires_new: true) do
      connection.select_one(<<~SQL)
        SELECT state, xact_start::text AS xact_start, left(query, 200) AS query FROM pg_stat_activity WHERE pid = #{Integer(pid)}
      SQL
    end
    return "状態は引けなかった（接続が終わった）" if row.nil? || row["state"].nil?

    "状態 #{row['state']}、トランザクションの開始 #{row['xact_start'] || 'なし'}、最後の問い合わせ #{row['query']}"
  rescue StandardError => e
    "状態は引けなかった（#{e.class}: #{e.message.lines.first&.strip}）"
  end
  private_class_method :activity

  # 残ったポリシーを外すコマンド。bin/rails runner は spec/support を読まないので、2 つの補助を読み込ませる
  def self.remove_command
    database = OwnerConnection.connection_db_config.database
    env = [ "RAILS_ENV=test", ("TEST_DATABASE=#{database}" unless database == DEFAULT_TEST_DATABASE) ].compact.join(" ")
    "#{env} bin/rails runner 'require \"./spec/support/matrix_world\"; require \"./spec/support/matrix_cross_read\"; " \
      "MatrixCrossRead.remove!'"
  end
  private_class_method :remove_command
end
