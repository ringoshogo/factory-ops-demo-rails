require_relative "boot"
require_relative "../packs/platform/lib/platform/request_context"

require "rails"
# Pick the frameworks you want:
# Active Storage・Action Mailbox・Action Text・Action Cable は読み込まない。読み込まれた部品があると、読む人がそれを使える前提で
# 設計する。足すときは docs/guides/config.md「使っていない機能の設定」の表を直す
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module FactoryOpsDemoRails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # lib/rubocop はカスタム Cop で、rubocop の gem が無いアプリの起動では読めない。
    # lib/schema_compat.rb も、開発とテストのグループにだけある graphql-schema_comparator を読むので同じ
    config.autoload_lib(ignore: %w[assets tasks rubocop schema_compat.rb])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # ログインを Cookie のセッションで保つ（docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」1）。
    # API モードは CSRF 対策を持たないので、SameSite=Lax で他サイトからの POST に Cookie を付けさせず、
    # 受け付ける本文を application/json に限る（ApplicationController）
    # 期限は最後のリクエストから数える。ログアウトとパスワードの変更の後の Cookie は、ユーザーのセッションの世代で拒む
    config.session_store :cookie_store, key: "_factory_ops_session", same_site: :lax, secure: Rails.env.production?,
      expire_after: 12.hours
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    # RLS のポリシーと複合外部キーを残すため（adr/001）
    config.active_record.schema_format = :sql

    # 要求 ID と相関 ID を、要求の開始のイベントより外側で文脈に設定する。全環境で入れる。
    # 本番とテストは直後の Rails::Rack::Logger を外す（Platform::Logging.configure!）が、Rails は挿入を当ててから削除を当てるので、
    # この位置に残る（docs/guides/config.md「ログ」）
    config.middleware.insert_before Rails::Rack::Logger, Platform::RequestContext

    # Solid Queue を業務 DB と同じ接続に置く。connects_to を設定せず、全環境で同じアダプタにする（docs/adr/005 決定 1）
    config.active_job.queue_adapter = :solid_queue

    # 通知のメールの差出人。送信先（provider）は環境ごとに決め、決めない環境は起動時に例外にする（Notifications::Provider）
    config.x.notifications.from = "notifications@factory-ops.example"
  end
end
