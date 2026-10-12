// サーバーでだけ読む設定。Rails の URL はブラウザに出さない。ブラウザは Next のサーバーだけを呼び、
// Next のサーバーが Rails を呼ぶので、Rails の CORS を開けずに済む (docs/guides/config.md「CSRF を防ぐ前提：CORS を開けない」)。

/** Rails の URL。未設定なら手元の bin/rails server の既定のポートを呼ぶ。 */
export const RAILS_URL = process.env.RAILS_URL ?? "http://127.0.0.1:3000";

/**
 * Rails の応答を待つ上限。超えたら「API に届かない」として扱う。開発の Rails は最初の要求でコードを読み込むので、
 * 数秒では足りないことがある。
 */
export const RAILS_TIMEOUT_MS = 10_000;

/** Rails のセッションの Cookie の名前 (config/application.rb の session_store の key)。 */
export const SESSION_COOKIE = "_factory_ops_session";
