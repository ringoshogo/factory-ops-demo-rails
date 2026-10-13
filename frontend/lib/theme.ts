/**
 * テーマの選択。Cookie `theme` に `light` / `dark` を持ち、
 * 無ければ OS の設定に従う。サーバー (レイアウト) とクライアント (切替ボタン) の
 * 両方が読むので、値の解釈はここにだけ置く。
 */
export const THEME_COOKIE = "theme";

export type ThemeChoice = "system" | "light" | "dark";

export const THEME_LABELS: Record<ThemeChoice, string> = {
  system: "OS に合わせる",
  light: "ライト",
  dark: "ダーク",
};

/** 切替ボタンを押したときの次の選択: OS → ライト → ダーク → OS。 */
export function nextTheme(current: ThemeChoice): ThemeChoice {
  return current === "system" ? "light" : current === "light" ? "dark" : "system";
}

export function parseTheme(value: string | undefined): ThemeChoice {
  return value === "light" || value === "dark" ? value : "system";
}

/** `<html>` に付けるクラス。OS に従うときは付けない (CSS の prefers-color-scheme に任せる)。 */
export function themeClass(choice: ThemeChoice): string {
  return choice === "system" ? "" : choice;
}

/** `<html>` のクラスから今の選択を読む (`themeClass` の逆)。 */
export function themeFromClassList(classList: DOMTokenList): ThemeChoice {
  return classList.contains("dark") ? "dark" : classList.contains("light") ? "light" : "system";
}
