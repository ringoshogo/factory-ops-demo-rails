import accounts from "../../db/seeds/demo_accounts.json";

/**
 * シードのアカウントの一覧。シード (lib/demo_world.rb) とログインの画面が同じファイルを読み、片方だけが古くならない。
 * パスワードはデモの手元で使う共通の値で、本番の資格情報ではない。
 */
export type DemoAccount = { persona: string; tenant: string; role: string; email: string; name: string };

export const DEMO_PASSWORD: string = accounts.password;
export const DEMO_ACCOUNTS: readonly DemoAccount[] = accounts.accounts;

/**
 * テナントの鍵 (demo_accounts.json の tenant) ごとの見出し。会社名は lib/demo_world.rb にだけ置き、ここでは
 * シードでの立場だけを書く。
 */
export const TENANT_LABELS: Record<string, string> = {
  supplier: "受注側の部品メーカー",
  granted_buyer: "発注側の組立メーカー（全権限の付与あり）",
  revoked_buyer: "発注側の組立メーカー（取引関係は失効済み）",
};
