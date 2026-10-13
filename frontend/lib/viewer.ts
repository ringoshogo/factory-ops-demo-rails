import { cache } from "react";
import { ViewerShellDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";

/**
 * ログインしているユーザーと自社テナント。レイアウトと画面の両方が読むので、1 回の描画で Rails を 1 回だけ呼ぶ。
 * 届かなければ null で、レイアウトは名前を出さずに枠だけを描く。
 */
export const loadViewer = cache(async () => {
  const result = await query(ViewerShellDocument);
  return result.kind === "ok" ? result.data.viewer : null;
});

/** `admin` に限る操作のボタンを出すか。Rails の規則が拒むボタンを出さない (docs/architecture/graphql-schema.md「役割による制限」)。 */
export async function isAdmin(): Promise<boolean> {
  return (await loadViewer())?.role === "admin";
}
