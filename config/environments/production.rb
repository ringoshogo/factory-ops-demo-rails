require "active_support/core_ext/integer/time"
require_relative "../../packs/platform/lib/platform/logging"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # TLS は前段（公開の配置では Cloudflare）で終わり、Rails には Next のサーバーから http で届く。http の要求のままでは
  # actionpack が Secure のセッションの Cookie を応答に書かず、ログインできないので、要求を https として扱う（docs/adr/009 決定 2）
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # 1 行 1 件の JSON を標準出力に書く。要求 ID はタグではなく文脈から入る（docs/guides/config.md「ログ」）
  Platform::Logging.configure!(config, STDOUT)

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  # info より細かい水準は、初期化の後のロガーで確かめて起動を止める（docs/guides/config.md「ログ」）
  config.after_initialize { Platform::Logging.verify_production_level!(Rails.logger) }

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :resque

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # 通知のメールは SMTP ではなく、Notifications::Mailer の配送の方法から SendGrid の API へ送る（docs/adr/007 決定 5）。
  # API キーと Webhook の署名の公開鍵は credentials に置き、リポジトリとログに書かない
  # 公開の配置のアカウントのメールアドレスは実在しないので、NOTIFICATIONS_PROVIDER=file_system で送り先をファイルに替える。
  # 打ち間違いで黙って SendGrid に送らないように、2 つのほかの値は起動で落とす（docs/guides/config.md「環境ごとの設定」）
  notifications_provider = ENV.fetch("NOTIFICATIONS_PROVIDER", "sendgrid")
  unless %w[sendgrid file_system].include?(notifications_provider)
    raise ArgumentError, "NOTIFICATIONS_PROVIDER は sendgrid か file_system にする: #{notifications_provider.inspect}"
  end
  config.x.notifications.provider = notifications_provider.to_sym
  config.x.notifications.sendgrid_sandbox = false
  config.x.notifications.sendgrid_api_key = Rails.application.credentials.dig(:sendgrid, :api_key)
  config.x.notifications.sendgrid_webhook_public_key = Rails.application.credentials.dig(:sendgrid, :webhook_public_key)

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
