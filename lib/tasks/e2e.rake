# E2E の世界の準備（lib/e2e_prepare.rb）。frontend/e2e/start-rails.sh が、E2E の Rails を起こす前に、
# e2e:check・db:drop・db:prepare・e2e:prepare の順に別のコマンドで流す。DB を消して作り直す工程は、DemoWorld を読み込んだ
# プロセスの中で呼ぶと、作り直した DB に構造を読み込まずに終わる（rails 8.1 の db:prepare は、同じプロセスで既に
# 接続を確かめた設定を初期化済みと見なす）ので、別のコマンドに分ける
namespace :e2e do
  desc "E2E の DB を作り直してよいかを確かめる。test の環境で TEST_DATABASE を渡し、bin/jobs が動いていないこと"
  task check: :environment do
    require Rails.root.join("lib/e2e_prepare").to_s
    E2ePrepare.check_target!(env: Rails.env, database: ENV["TEST_DATABASE"])
    begin
      E2ePrepare.check_no_workers!("前")
    rescue ActiveRecord::NoDatabaseError
      # DB がまだ無ければ、ワーカーも登録されていない
    rescue ActiveRecord::StatementInvalid => error
      # 表がまだ無ければ、ワーカーも登録されていない。権限の不足のような別の失敗では、守りを外さずに止まる
      raise unless error.cause.is_a?(PG::UndefinedTable)
    end
  rescue E2ePrepare::Refused => error
    abort "e2e:check: #{error.message}"
  end

  desc "ワーカーの数（既定 1）だけ E2E の世界を作り、アカウントを tmp/e2e/worlds.json に書く。作り直した空の DB に流す"
  task :prepare, [ :workers ] => :environment do |_task, args|
    require Rails.root.join("lib/e2e_prepare").to_s
    E2ePrepare.check_target!(env: Rails.env, database: ENV["TEST_DATABASE"])
    workers = Integer(args[:workers] || 1)
    worlds = E2ePrepare.worlds(workers)
    E2ePrepare.check_no_workers!("後")
    E2ePrepare.write(worlds)
    puts "e2e:prepare: #{workers} 組の世界を作り、#{E2ePrepare::ACCOUNTS_PATH} に書いた"
  rescue E2ePrepare::Refused => error
    abort "e2e:prepare: #{error.message}"
  end
end
