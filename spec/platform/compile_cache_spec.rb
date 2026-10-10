require "rails_helper"
require "open3"
require "tmpdir"

# テストの環境は、bootsnap の命令列のキャッシュを使わない（docs/guides/config.md「boot.rb で変えたこと」）。
# bootsnap は大きさと更新時刻（秒）が同じファイルをキャッシュから返すので、実装を壊して戻す確かめで、
# 同じ秒に同じ大きさで書き戻したファイルの古い版を読む
RSpec.describe "テストの環境の命令列のキャッシュ" do
  # 子のプロセスで config/boot.rb を読み、渡したファイルを require して定数の値を出す。
  # キャッシュの置き場は example ごとの一時ディレクトリにし、ほかの実行のキャッシュと混ぜない
  def load_value(path, cache_dir)
    env = { "RAILS_ENV" => "test", "BOOTSNAP_CACHE_DIR" => cache_dir }
    script = "require #{Rails.root.join('config/boot').to_s.dump}; require #{path.dump}; print CompileCacheProbe::VALUE"
    output, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, unsetenv_others: false)
    expect(status).to be_success, output
    output
  end

  it "同じ秒に同じ大きさで書き換えたファイルを、書き換えた後の中身で読む" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "compile_cache_probe.rb")
      File.write(path, "module CompileCacheProbe; VALUE = 1; end\n")
      stamp = File.mtime(path)
      expect(load_value(path, File.join(dir, "cache"))).to eq("1")

      File.write(path, "module CompileCacheProbe; VALUE = 2; end\n")
      File.utime(stamp, stamp, path)

      expect(load_value(path, File.join(dir, "cache"))).to eq("2")
    end
  end
end
