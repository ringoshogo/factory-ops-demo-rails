# 一時の DB の一覧と削除（lib/temp_databases.rb）。担当を止めるときに、取りまとめ役が一覧を読み、その担当の DB を名前で消す
# （docs/guides/bin.md）。test の環境でだけ動く
namespace :temp_databases do
  desc "一時の DB（TEST_DATABASE・E2E_DATABASE で作ったもの）を、接続の数と一緒に出す。RAILS_ENV=test で流す"
  task list: :environment do
    require Rails.root.join("lib/temp_databases").to_s
    rows = TempDatabases.list(env: Rails.env)
    puts "一時の DB は無い" if rows.empty?
    rows.each { |name, count| puts "#{name}\t接続 #{count}" }
  rescue TempDatabases::Refused => error
    abort "temp_databases:list: #{error.message}"
  end

  desc "名前を明示した一時の DB を消す（FORCE なし。接続中なら失敗する）。RAILS_ENV=test で流す"
  task :drop, [ :name ] => :environment do |_task, args|
    require Rails.root.join("lib/temp_databases").to_s
    TempDatabases.drop!(args[:name], env: Rails.env)
    puts "temp_databases:drop: #{args[:name]} を消した"
  rescue TempDatabases::Refused => error
    abort "temp_databases:drop: #{error.message}"
  end
end
