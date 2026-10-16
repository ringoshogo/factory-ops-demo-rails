require "rails_helper"
require "open3"

# E2E の Rails は、手元でも CI と同じく起動の時にアプリを読み込む（docs/guides/config.md「環境ごとの設定」）。
# 変数を外しても手元の E2E は通るので、外した変更が黙って入らないよう、test の環境の設定と起動のスクリプトの両方を照らす
RSpec.describe "E2E の起動の時の読み込み" do
  # 子のプロセスで test の環境を初期化し、eager_load の値を返す。親のプロセスの CI（CI では true）が入り込むと、
  # どちらの example も E2E_EAGER_LOAD だけでは決まらないので、CI は消す
  def eager_load_with(env)
    source = <<~RUBY
      require "./config/application"
      Rails.application.initialize!
      puts "SPEC_RESULT " + JSON.generate(eager_load: Rails.application.config.eager_load)
    RUBY
    output, status = Open3.capture2e({ "RAILS_ENV" => "test", "CI" => nil }.merge(env), RbConfig.ruby, "-e", source, chdir: Rails.root.to_s)
    expect(status).to be_success, output
    JSON.parse(output.lines.grep(/\ASPEC_RESULT /).sole.delete_prefix("SPEC_RESULT ")).fetch("eager_load")
  end

  it "E2E_EAGER_LOAD=1 を渡したときだけ、test の環境が起動の時に読み込む" do
    expect(eager_load_with("E2E_EAGER_LOAD" => nil)).to be(false)
    expect(eager_load_with("E2E_EAGER_LOAD" => "1")).to be(true)
  end

  # スクリプトは DB を作り直してサーバーを起こすので、流さずに行を読む
  it "frontend/e2e/start-rails.sh が、bin/rails を呼ぶ行より前に E2E_EAGER_LOAD=1 を渡す" do
    lines = Rails.root.join("frontend/e2e/start-rails.sh").readlines(chomp: true).reject { _1.lstrip.start_with?("#") }
    export = lines.index("export E2E_EAGER_LOAD=1")
    first_rails = lines.index { _1.match?(%r{\bbin/rails\b}) }

    # 対照：スクリプトは bin/rails を呼ぶ
    expect(first_rails).not_to be_nil
    expect(export).not_to be_nil
    expect(export).to be < first_rails
  end
end
