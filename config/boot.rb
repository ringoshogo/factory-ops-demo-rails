ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# テストの環境では bootsnap の命令列のキャッシュを使わない。bootsnap は大きさと更新時刻（秒）が同じファイルを
# キャッシュから返すので、実装を壊して戻す確かめで、同じ秒に同じ大きさで書き戻したファイルの古い版を読む
# （docs/guides/config.md「boot.rb で変えたこと」）
ENV["DISABLE_BOOTSNAP_COMPILE_CACHE"] ||= "1" if ENV["RAILS_ENV"] == "test"

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
