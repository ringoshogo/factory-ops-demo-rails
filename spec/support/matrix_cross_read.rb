require_relative "owner_connection"

# 入口の行列の 2 回目のために、テナントの表ごとに、設定 app.matrix_cross_read が on のときだけ全行を読ませる
# SELECT のポリシーを足し外す（docs/guides/testing.md「行列テストとの分担」）。RLS が他社の行を隠すと、
# 公開 API の scope を外しても応答が変わらないので、RLS の SELECT を開いた応答と比べて scope の抜けを捕まえる。
# アプリのロールは app.* の設定を自由に変えられるので、このポリシーが本番に載れば全テナントの行を読む抜け道になる。
# そのため SQL はここにだけ置き、lib/tenant_table.rb とマイグレーションには置かない。
# structure.sql に混ざれば bin/check-structure が、消し忘れれば spec/db/tenant_enforcement_spec.rb が落とす
module MatrixCrossRead
  POLICY = "matrix_cross_read".freeze
  SETTING = "app.matrix_cross_read".freeze

  # 所有ロールの接続で、全表のポリシーを 1 つのトランザクションで足す。途中で失敗すると全部が巻き戻り、足した分は残らない。
  # 世界を開く前に呼ぶ。ポリシーの足し外しは表のロックを取るので、全表に書いた世界の外側のトランザクションが開いている間は、
  # それが閉じるまで待ち、世界と同じスレッドから呼ぶと終わらない。
  # 同じ名前のポリシーがあれば、別の実行が同じテストの DB で行列を流しているか、途中で止めた実行が残したので、外さずに失敗する
  def self.add!
    with_owner_connection do |connection|
      connection.transaction do
        MatrixWorld.tenant_tables.each do |table|
          connection.execute(<<~SQL)
            CREATE POLICY #{POLICY} ON #{connection.quote_table_name(table)} FOR SELECT
              USING (current_setting('#{SETTING}', true) = 'on')
          SQL
        end
      end
    end
  rescue ActiveRecord::StatementInvalid => e
    raise unless e.cause.is_a?(PG::DuplicateObject)

    raise "#{POLICY} のポリシーがすでにある。同じテストの DB で行列を流しているほかの実行が無ければ、" \
      "途中で止めた実行が残したものなので、MatrixCrossRead.remove! で外す（docs/guides/testing.md「行列テストとの分担」）"
  end

  # 足していない表があっても失敗しない
  def self.remove!
    with_owner_connection do |connection|
      connection.transaction do
        MatrixWorld.tenant_tables.each { connection.execute("DROP POLICY IF EXISTS #{POLICY} ON #{connection.quote_table_name(_1)}") }
      end
    end
  end

  # example のトランザクションの中だけで RLS の SELECT を開く。example のセーブポイントを巻き戻すと設定も戻る。
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

      yield connection
    end
  end
  private_class_method :with_owner_connection
end
