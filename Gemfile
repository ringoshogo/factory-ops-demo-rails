source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.4"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Flag unsafe schema changes before they run [https://github.com/ankane/strong_migrations]
gem "strong_migrations"
# Autoload packs/*/app/* [https://github.com/rubyatscale/packs-rails]
gem "packs-rails", "~> 0.1.0"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"
# Use Redis adapter to run Action Cable in production
# gem "redis", ">= 4.0.1"

# GraphQL の API [https://graphql-ruby.org]
gem "graphql", "~> 2.6"
# 認可の policy と、その GraphQL との連携 [https://actionpolicy.evilmartians.io]
gem "action_policy-graphql", "~> 0.6"

# ジョブ基盤。業務 DB と同じ接続に置き、イベントのジョブを業務のトランザクションの中で登録する（docs/adr/005）
gem "solid_queue", "~> 1.2"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rspec-rails"
  gem "factory_bot_rails"

  # Enforce package dependencies and privacy [https://github.com/Shopify/packwerk]
  gem "packwerk", "~> 3.3", require: false
  gem "packwerk-extensions", "~> 0.4.0", require: false

  # 関連を 1 件ずつ読む N+1 を検出する。テストでは例外に、開発ではログにする [https://github.com/flyerhzm/bullet]
  gem "bullet", "~> 8.2"

  # 基準と作業中の GraphQL のスキーマを比べ、変更を破壊・危険・非破壊に分ける。判定は lib/schema_compat.rb が行う
  # [https://github.com/xuorig/graphql-schema_comparator]
  gem "graphql-schema_comparator", "~> 1.2", require: false
end
