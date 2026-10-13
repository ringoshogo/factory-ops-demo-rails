"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { SESSION_COOKIE } from "@/lib/config";
import type { FormState } from "@/lib/form-state";
import { ViewerLandingDocument } from "@/lib/graphql/generated";
import { createSession, destroySession, queryAs } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { writeSessionCookie } from "@/lib/session";

/**
 * Rails の POST /session に資格情報を送り、応答のセッションの Cookie を、同じ属性でこのオリジンの Cookie に写す。
 * ログインの直後は、受注側の取引関係があれば受注側のダッシュボードへ、無ければ発注側の発注一覧へ移す。
 * テナントは発注側と受注側のどちらにもなりうるので、取引関係の有無で、そのテナントがいま主に使う側を決める。
 */
export async function login(_prev: FormState, form: FormData): Promise<FormState> {
  const email = String(form.get("email") ?? "").trim();
  const password = String(form.get("password") ?? "");
  const result = await createSession(email, password);
  if (result.kind === "unreachable") return { status: "error", message: UNREACHABLE_MESSAGE };
  if (result.kind === "invalid") return { status: "error", message: "メールアドレスかパスワードが違います。" };

  writeSessionCookie(await cookies(), result.cookie);
  const landing = await queryAs(result.cookie, ViewerLandingDocument);
  const supplierSide = landing.kind === "ok" && landing.data.supplier.partnerships.length > 0;
  redirect(supplierSide ? "/supplier/dashboard" : "/buyer/purchase-orders");
}

/** Rails の DELETE /session を呼んで（共有のデモのアカウントの配置では世代を進めない）から、このオリジンの Cookie を消す。 */
export async function logout(): Promise<void> {
  await destroySession();
  (await cookies()).delete(SESSION_COOKIE);
  redirect("/");
}
