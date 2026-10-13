import { cookies } from "next/headers";
import { cache } from "react";
import { parseTheme, THEME_COOKIE, type ThemeChoice } from "./theme";

/** Cookie のテーマ選択 (サーバー側)。複数のレイアウトが読むのでリクエストごとに1回だけ。 */
export const readTheme = cache(
  async (): Promise<ThemeChoice> => parseTheme((await cookies()).get(THEME_COOKIE)?.value),
);
