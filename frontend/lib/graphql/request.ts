import type { TypedDocumentNode } from "@graphql-typed-document-node/core";
import { print } from "graphql";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { RAILS_TIMEOUT_MS, RAILS_URL, SESSION_COOKIE } from "@/lib/config";
import { copySessionCookie, EXPIRED_PATH, readSessionCookie, type SessionCookie } from "@/lib/session";

/**
 * Rails の GraphQL を呼ぶ唯一の口。画面は応答を次の 3 つに分けた結果だけを見る。
 *
 * - `ok`: data が返った。mutation のユーザーエラー (`errors: [UserError]`) は data の中にあり、画面が `lib/graphql/user-errors.ts` で分ける
 * - `unreachable`: 接続できない・5xx・時間切れ。画面は「API に届かない」の表示を出す
 * - `error`: トップレベルのエラー (FORBIDDEN など)。画面の上に、処理できなかったことを出す
 *
 * HTTP 401 は結果として返さず、セッションの Cookie を消してログインの画面へ移す。
 */
export type GraphQLResult<T> =
  | { kind: "ok"; data: T }
  | { kind: "unreachable" }
  | { kind: "error"; message: string };

type Variables = Record<string, unknown>;

const FAILED = "処理できませんでした。画面を読み直してから、もう一度お試しください。";

/** 読み取り。サーバーコンポーネントから呼ぶ。サーバーコンポーネントは Cookie を書けないので、延びた期限は写さない。 */
export async function query<TData, TVariables extends Variables>(
  document: TypedDocumentNode<TData, TVariables>,
  ...[variables]: VariablesArg<TVariables>
): Promise<GraphQLResult<TData>> {
  return execute(document, variables ?? {}, { writeCookie: false });
}

/**
 * 書き込みと、server action の中の読み取り。Rails が応答のたびに期限を延ばして書き直すセッションの Cookie を、
 * ブラウザへ写す。サーバーコンポーネントの読み取りでは写せないので、読むだけの利用では、期限はログインか
 * 最後の書き込みから 12 時間になる。
 */
export async function mutate<TData, TVariables extends Variables>(
  document: TypedDocumentNode<TData, TVariables>,
  ...[variables]: VariablesArg<TVariables>
): Promise<GraphQLResult<TData>> {
  return execute(document, variables ?? {}, { writeCookie: true });
}

/**
 * ログインの直後の読み取り。server action が書いたばかりの Cookie を、ブラウザから届いた Cookie の代わりに送る。
 * 同じ action の中では、書いた Cookie が届いた Cookie として読める保証が Next の文書に無いからである。
 */
export async function queryAs<TData, TVariables extends Variables>(
  session: SessionCookie,
  document: TypedDocumentNode<TData, TVariables>,
  ...[variables]: VariablesArg<TVariables>
): Promise<GraphQLResult<TData>> {
  return execute(document, variables ?? {}, { writeCookie: true, session: session.value });
}

export type LoginResult = { kind: "ok"; cookie: SessionCookie } | { kind: "invalid" } | { kind: "unreachable" };

/** Rails の POST /session に資格情報を送り、応答のセッションの Cookie を返す。Cookie を書くのは呼んだ server action である。 */
export async function createSession(email: string, password: string): Promise<LoginResult> {
  let res: Response;
  try {
    res = await fetch(`${RAILS_URL}/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
      cache: "no-store",
      signal: AbortSignal.timeout(RAILS_TIMEOUT_MS),
    });
  } catch {
    return { kind: "unreachable" };
  }
  if (res.status === 401) return { kind: "invalid" };
  const cookie = res.ok ? readSessionCookie(res) : null;
  return cookie ? { kind: "ok", cookie } : { kind: "unreachable" };
}

/**
 * Rails の DELETE /session を呼び、ユーザーのセッションの世代を進める。Cookie のセッションはサーバーに残らないので、
 * ブラウザの Cookie を消すだけでは、写し取られた Cookie が使えるまま残る。届かなくても、呼んだ側は Cookie を消す。
 */
export async function destroySession(): Promise<void> {
  const session = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!session) return;
  try {
    await fetch(`${RAILS_URL}/session`, {
      method: "DELETE",
      headers: { "Content-Type": "application/json", Cookie: `${SESSION_COOKIE}=${session}` },
      cache: "no-store",
      signal: AbortSignal.timeout(RAILS_TIMEOUT_MS),
    });
  } catch {
    // 届かなければ世代は進まない。Cookie は呼んだ側が消すので、このブラウザからは使えなくなる
  }
}

// 変数を持たない操作は引数を省ける
type VariablesArg<T> = Record<string, never> extends T ? [variables?: T] : [variables: T];

async function execute<TData, TVariables extends Variables>(
  document: TypedDocumentNode<TData, TVariables>,
  variables: TVariables | Record<string, never>,
  { writeCookie, session: given }: { writeCookie: boolean; session?: string },
): Promise<GraphQLResult<TData>> {
  const jar = await cookies();
  const session = given ?? jar.get(SESSION_COOKIE)?.value;
  if (!session) redirect("/");

  let res: Response;
  try {
    res = await fetch(`${RAILS_URL}/graphql`, {
      method: "POST",
      // ApplicationController は application/json の本文だけを受け付ける (他サイトのフォームからの CSRF を防ぐ)
      headers: { "Content-Type": "application/json", Cookie: `${SESSION_COOKIE}=${session}` },
      body: JSON.stringify({ query: print(document), variables, operationName: operationName(document) }),
      // セッションごとに応答が違うので、Next のデータのキャッシュに載せない。キャッシュの鍵にセッションが入らず、
      // あるテナントへの応答を別のテナントに返すことになる
      cache: "no-store",
      signal: AbortSignal.timeout(RAILS_TIMEOUT_MS),
    });
  } catch {
    return { kind: "unreachable" };
  }

  // サーバーコンポーネントは Cookie を消せないので、消す役は route handler に任せる
  if (res.status === 401) redirect(EXPIRED_PATH);
  if (res.status >= 500) return { kind: "unreachable" };
  if (!res.ok) return { kind: "error", message: FAILED };
  if (writeCookie) copySessionCookie(res, jar);

  let body: { data?: TData | null; errors?: { message: string }[] };
  try {
    body = await res.json();
  } catch {
    return { kind: "unreachable" };
  }
  if (body.errors?.length || !body.data) {
    return { kind: "error", message: FAILED };
  }
  return { kind: "ok", data: body.data };
}

function operationName(document: TypedDocumentNode<unknown, never>): string | undefined {
  const definition = document.definitions.find((d) => d.kind === "OperationDefinition");
  return definition && "name" in definition ? definition.name?.value : undefined;
}
