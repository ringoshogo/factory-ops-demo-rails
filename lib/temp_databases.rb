require "pg"

# 担当が TEST_DATABASE・E2E_DATABASE で作った一時の DB の一覧と削除（lib/tasks/temp_databases.rake、
# docs/guides/config.md「database.yml：同じ DB に 2 つのロールで接続する」）。作る入口（bin/ci の db:test:prepare、
# E2E の start-rails.sh の db:drop db:prepare）はあるが消す入口が無く、担当を止めた後に一時の DB が残り続けるので置く。
# 消すのは名前を明示したときだけにし、名前の規則に合わない名前と既定の 3 つの DB は拒む。作者の開発の DB や、
# rspec・E2E の既定の DB を一覧の取り違えで消さないためである
class TempDatabases
  class Refused < StandardError; end

  # 担当ごとに名前を替えずに使う DB。一時の DB の名前の規則に合っても、一覧に出さず、消さない
  DEFAULTS = %w[factory_ops_demo_rails_development factory_ops_demo_rails_test factory_ops_e2e].freeze

  # 一時の DB の名前の規則。factory_ops_ で始まり、_ で区切った語に test か e2e を含む（factory_ops_m51_test・factory_ops_m51_e2e）。
  # 語として照らすので、factory_ops_m51_testing のように語の一部に含むだけの名前は当たらない
  def self.temporary?(name)
    name.to_s.match?(/\Afactory_ops_[a-z0-9_]+\z/) && name.split("_").intersect?(%w[test e2e]) && !DEFAULTS.include?(name)
  end

  # 一時の DB の名前と、いまの接続の数を、名前の順に返す
  def self.list(env:)
    check_env!(env)
    with_maintenance_connection do |connection|
      connection.exec(<<~SQL).values.map { |name, count| [ name, Integer(count) ] }.select { |name, _| temporary?(name) }
        SELECT d.datname, count(a.pid) FROM pg_database d LEFT JOIN pg_stat_activity a ON a.datid = d.oid
        WHERE NOT d.datistemplate GROUP BY d.datname ORDER BY d.datname
      SQL
    end
  end

  # 名前を明示した一時の DB を消す。FORCE を付けないので、接続中の DB は PostgreSQL が失敗させ、その失敗をそのまま出す。
  # 動いている担当の DB を、その担当の接続ごと切って消さないためである
  def self.drop!(name, env:)
    check_env!(env)
    raise Refused, "消す DB の名前を明示する" if name.blank?
    raise Refused, "#{name} は一時の DB の名前の規則に合わないか、既定の DB なので消さない" unless temporary?(name)

    # DROP DATABASE はトランザクションの中で流せない。PG の接続は既定で自動コミットなので、文を 1 つだけ流す
    with_maintenance_connection { |connection| connection.exec("DROP DATABASE #{connection.quote_ident(name)}") }
  end

  def self.check_env!(env)
    raise Refused, "一時の DB のタスクは test の環境でだけ動く: #{env}" unless env.to_s == "test"
  end
  private_class_method :check_env!

  # 所有ロールで保守用の DB（postgres）に接続する。消す DB に接続したままでは消せないからである
  def self.with_maintenance_connection
    config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "owner").configuration_hash
    connection = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password],
      dbname: "postgres")
    yield connection
  ensure
    connection&.close
  end
  private_class_method :with_maintenance_connection
end
