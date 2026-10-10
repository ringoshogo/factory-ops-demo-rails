require_relative "owner_connection"

# 2 つの接続で同時に操作する競合テストの補助（docs/guides/testing.md「競合テスト」）。
# 例ごとのトランザクションの中では接続が 1 本に固定されるので、使う側は use_transactional_tests を false にし、
# 作った行を例の後で所有ロールの接続（delete_owned_rows）で消す
module ConcurrencyHelpers
  # 別のスレッドでテナントのトランザクションを開いてブロックを実行し、[結果, release, スレッド] を返す。
  # トランザクションは release に値を積むまでコミットしない
  def hold_open(tenant_id, &block)
    ready = Queue.new
    release = Queue.new
    thread = Thread.new do
      Tenancy.with_tenant(tenant_id) do
        ready << block.call
        release.pop
      end
    rescue StandardError => e
      ready << e
    end
    concurrency_releases << release
    concurrency_threads << thread
    result = ready.pop
    raise result if result.is_a?(Exception)

    [ result, release, thread ]
  end

  # 別のスレッドでテナントのトランザクションを開いてブロックを実行する。結果はスレッドの value で受け取る
  def in_thread(tenant_id, &block)
    Thread.new { Tenancy.with_tenant(tenant_id, &block) }.tap do |thread|
      thread.report_on_exception = false
      concurrency_threads << thread
    end
  end

  # スレッドが終わる前にロックの待ちに入れば真、待たずに終われば偽
  def blocked_on_lock?(thread)
    50.times do
      return false unless thread.alive?

      waiting = ApplicationRecord.with_connection do |connection|
        connection.select_value(<<~SQL)
          SELECT count(*) FROM pg_stat_activity
          WHERE datname = current_database() AND wait_event_type = 'Lock' AND pid <> pg_backend_pid()
        SQL
      end
      return true if waiting.positive?

      sleep 0.1
    end
    raise "スレッドがロックを待たずに止まっている"
  end

  # 期待が外れて途中で抜けても、開いたままのトランザクションを閉じ、スレッドを終わらせる。
  # スレッドの例外は例の中で確かめ済みなので捨てる
  def finish_concurrent_threads
    concurrency_releases.each { _1 << true }
    concurrency_threads.each do |thread|
      thread.join(10)
    rescue StandardError
      nil
    end
  end

  # tables の行のうち、tenant_ids のテナントが所有する行と、そのテナントを宛先にしたイベントのジョブと、テナントを消す。
  # 子の表から先に並べる
  def delete_owned_rows(tenant_ids, tables)
    connection = OwnerConnection.lease_connection
    ids = tenant_ids.map { connection.quote(_1) }.join(", ")
    connection.transaction do
      tables.each { connection.execute("DELETE FROM #{_1} WHERE owner_tenant_id IN (#{ids})") }
      tenant_ids.each do |tenant_id|
        connection.execute("DELETE FROM solid_queue_jobs WHERE arguments LIKE #{connection.quote("%#{tenant_id}%")}")
      end
      connection.execute("DELETE FROM tenants WHERE id IN (#{ids})")
    end
  end

  private

  def concurrency_threads = (@concurrency_threads ||= [])
  def concurrency_releases = (@concurrency_releases ||= [])
end

RSpec.configure do |config|
  config.include ConcurrencyHelpers, :concurrency
  config.after(:each, :concurrency) { finish_concurrent_threads }
end
