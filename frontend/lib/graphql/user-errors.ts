import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import type { FormState } from "@/lib/form-state";
import type { GraphQLResult } from "@/lib/graphql/request";

/** mutation の応答の UserError (schema.graphql の UserError)。 */
export type UserError = { code: string; message: string; path: readonly string[] | null };

/** 見つからない画面 (app/(app)/missing/page.tsx)。mutation の NOT_FOUND はここへ移す。 */
export const MISSING_PATH = "/missing";

export const UNREACHABLE_MESSAGE = "API に接続できませんでした。時間をおいてもう一度お試しください。";

/**
 * NOT_PERMITTED の文言。失効・付与なし・存在しない相手のどれなのかを、画面で推し量って言い分けない
 * (docs/architecture/graphql-schema.md「ID と `node`」)。
 */
export const NOT_PERMITTED_MESSAGE = "この取引先とは、この操作をできません。取引関係と権限の付与を確かめてください。";

/**
 * mutation の結果を、フォームの結果に分ける。NOT_FOUND は見つからない画面へ移し、無いのか見えないのかを言い分けない。
 * `revalidate` は、成功したときと CONFLICT のときに読み直す画面の道。CONFLICT は最新の状態を読み直してから文言を出す。
 * ユーザーエラーの文言は API のものをそのまま出し、次にすることを書き足すときだけ言葉を足す。
 */
export function settle<T>(
  result: GraphQLResult<T>,
  pick: (data: T) => { errors: readonly UserError[] },
  revalidate: readonly string[],
): FormState {
  if (result.kind === "unreachable") return { status: "error", message: UNREACHABLE_MESSAGE };
  if (result.kind === "error") return { status: "error", message: result.message };

  const errors = pick(result.data).errors;
  if (errors.length === 0) {
    for (const path of revalidate) revalidatePath(path);
    return { status: "ok" };
  }
  return fromUserErrors(errors, revalidate);
}

function fromUserErrors(errors: readonly UserError[], revalidate: readonly string[]): FormState {
  if (errors.some((e) => e.code === "NOT_FOUND")) redirect(MISSING_PATH);
  if (errors.some((e) => e.code === "NOT_PERMITTED")) return { status: "error", message: NOT_PERMITTED_MESSAGE };

  if (errors.some((e) => e.code === "CONFLICT")) {
    for (const path of revalidate) revalidatePath(path);
    const conflict = errors.find((e) => e.code === "CONFLICT")!;
    return { status: "error", message: `${conflict.message}（最新の状態を読み直しました）` };
  }

  const fieldErrors: Record<string, string> = {};
  const messages: string[] = [];
  for (const error of errors) {
    if (error.path && error.path.length > 0) fieldErrors[error.path.join(".")] = error.message;
    else messages.push(error.message);
  }
  return {
    status: "error",
    message: messages.length > 0 ? messages.join(" ") : undefined,
    fieldErrors: Object.keys(fieldErrors).length > 0 ? fieldErrors : undefined,
  };
}
