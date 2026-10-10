require_relative "owner_connection"

# 2 つの接続で同時に操作する競合テストの補助（docs/guides/testing.md「競合テスト」）。
# 例ごとのトランザクションの中では接続が 1 本に固定されるので、使う側は use_transactional_tests を false にし、
# 作った業務の行を example の後で delete_owned_rows で消す。テナント・ユーザー・監査の行は残す
module ConcurrencyHelpers
  # 監査の行と、監査の行が指しうる行の表。監査の行は消せず、指す先も消さない
  KEPT_TABLES = %w[tenants users audit_logs].freeze

  # スレッドの終わりと、ロックの待ちを待つ上限の秒数
  WAIT_SECONDS = 10

  # 別のスレッドでテナントのトランザクションを開いてブロックを実行し、[ブロックの結果, release, スレッド] を返す。
  # トランザクションは release に値を積むまでコミットしない。コミットの結果は commit(release, スレッド) で受け取る。
  # ブロックの結果を返した後のコミットで例外が出ても、スレッドがそれを送出するので、commit が送出し直す
  def hold_open(tenant_id, &block)
    ready = Queue.new
    release = release_queue
    thread = Thread.new do
      Tenancy.with_tenant(tenant_id) do
        result = block.call
        ready << [ :held, result, current_backend_pid ]
        release.pop
        result
      end
    rescue StandardError => e
      ready << [ :failed, e ]
      raise
    end
    thread.report_on_exception = false
    concurrency_threads << thread

    state, result, pid = ready.pop
    raise result if state == :failed

    thread[:backend_pid] = pid
    [ result, release, thread ]
  end

  # hold_open で開いたトランザクションをコミットさせ、ブロックの結果を返す
  def commit(release, thread)
    release << true
    finish(thread)
  end

  # 別のスレッドでテナントのトランザクションを開いてブロックを実行する。スレッドの接続の pid を控えてから返す。
  # 結果は finish(スレッド) で受け取る
  def in_thread(tenant_id, &block)
    started = Queue.new
    thread = Thread.new do
      Tenancy.with_tenant(tenant_id) do
        started << current_backend_pid
        block.call
      end
    rescue StandardError
      started << nil
      raise
    end
    thread.report_on_exception = false
    concurrency_threads << thread
    thread[:backend_pid] = started.pop
    thread
  end

  # スレッドの終わりを待ち、ブロックの結果を返す。スレッドの例外は送出し直す。終わらなければ失敗する
  def finish(thread)
    raise "スレッドが #{WAIT_SECONDS} 秒で終わらない" unless thread.join(WAIT_SECONDS)

    thread.value
  end

  # thread の接続が、by の接続の持つロックを待っていれば真。待たずに終われば偽。どちらにもならなければ失敗する
  def blocked_on_lock?(thread, by:)
    waiter = thread[:backend_pid]
    holder = by[:backend_pid]
    raise "2 つのスレッドの接続の pid が分からないか、同じ接続を使っている" if waiter.nil? || holder.nil? || waiter == holder

    deadline = WAIT_SECONDS.seconds.from_now
    while Time.current < deadline
      return false unless thread.alive?

      blocked = ApplicationRecord.with_connection do |connection|
        connection.select_value("SELECT #{Integer(holder)} = ANY(pg_blocking_pids(#{Integer(waiter)}))")
      end
      return true if blocked

      sleep 0.05
    end
    raise "スレッドが #{WAIT_SECONDS} 秒のあいだ、ロックを待たずに止まっている"
  end

  # 途中で止めたスレッドを進めるための Queue。example の後で、finish_concurrent_threads が必ず値を積む
  def release_queue = Queue.new.tap { concurrency_releases << _1 }

  # 開いたままのトランザクションをすべて閉じさせ、スレッドの終わりを待つ。スレッドの例外は、example の中で
  # 確かめ済みか、example がすでに失敗しているので捨てる。終わらないスレッドがあれば失敗する
  def finish_concurrent_threads
    concurrency_releases.each { _1 << true }
    alive = concurrency_threads.reject do |thread|
      thread.join(WAIT_SECONDS)
    rescue StandardError
      true
    end
    raise "#{alive.size} 本のスレッドが #{WAIT_SECONDS} 秒で終わらない。行を消さずに止める" if alive.any?
  end

  # スレッドをすべて終わらせてから、tables の行のうち tenant_ids のテナントが所有する行と、そのテナントを宛先にした
  # イベントのジョブを消す。所有ロールの接続で消すのは、アプリのロールでは RLS が他のテナントの行を隠すからである。
  # tables は子の表から先に並べる。テナントとユーザーは、監査の行が指すので消さない（KEPT_TABLES）
  def delete_owned_rows(tenant_ids, tables)
    kept = tables & KEPT_TABLES
    raise ArgumentError, "#{kept.join('・')} の行は消さない（監査の行が指す）" if kept.any?

    finish_concurrent_threads
    connection = OwnerConnection.lease_connection
    ids = tenant_ids.map { connection.quote(_1) }.join(", ")
    connection.transaction do
      tables.each { connection.execute("DELETE FROM #{_1} WHERE owner_tenant_id IN (#{ids})") }
      tenant_ids.each do |tenant_id|
        connection.execute(<<~SQL)
          DELETE FROM solid_queue_jobs
          WHERE class_name = 'Contracts::EventJob' AND arguments LIKE #{connection.quote("%#{tenant_id}%")}
        SQL
      end
    end
  end

  private

  def current_backend_pid = ApplicationRecord.lease_connection.select_value("SELECT pg_backend_pid()")
  def concurrency_threads = (@concurrency_threads ||= [])
  def concurrency_releases = (@concurrency_releases ||= [])
end

RSpec.configure do |config|
  config.include ConcurrencyHelpers, :concurrency
end
