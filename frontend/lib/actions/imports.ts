"use server";

import { redirect } from "next/navigation";
import type { FormState } from "@/lib/form-state";
import { StartImportDocument, type ImportKind } from "@/lib/graphql/generated";
import { mutate } from "@/lib/graphql/request";
import { settle } from "@/lib/graphql/user-errors";

const KINDS: readonly ImportKind[] = ["ITEMS", "STOCKS"];

/**
 * 置いたファイルの取り込みを始め、進み具合の画面へ移る。ファイルはブラウザが /imports/files へ先に置き、返った ID を
 * ここへ渡す。種類 ITEMS を admin に限る規則は API が評価するので、画面の選択肢の出し分けだけに頼らない。
 */
export async function startImport(fileId: string, kind: string): Promise<FormState> {
  if (!KINDS.includes(kind as ImportKind)) return { status: "error", message: "取り込みの種類を選んでください。" };
  const result = await mutate(StartImportDocument, { input: { fileId, kind: kind as ImportKind } });
  const state = settle(result, (d) => d.startImport, ["/supplier/imports"]);
  const importId = result.kind === "ok" ? result.data.startImport.import?.id : undefined;
  if (state.status === "ok" && importId) redirect(`/supplier/imports/${importId}`);
  return state;
}
