import type { OrderDirection } from "@/lib/graphql/generated";
import { patchHref } from "@/lib/query";

/**
 * 一覧の画面の URL を、GraphQL の一覧の引数 (first・after・orderBy・filter) に写す。
 *
 * 一覧は 1 ページずつ読み、並べ替え・絞り込み・件数はサーバーが行う。画面は URL の値を変数に写すだけで、行を並べたり
 * 数えたりしない。同じ意味を画面とサーバーの 2 か所に持つと、片方だけが変わって件数と並びが食い違うからである。
 * 並べ替え・絞り込み・タブを変えると、次のページの位置 (`after`) を外して 1 ページ目に戻る。
 */
export const PAGE_SIZE = 20;

/** Next の `searchParams`。同じ名前の値が複数あれば配列になる。 */
export type SearchParams = Record<string, string | string[] | undefined>;

/** Next の `searchParams` を URLSearchParams に直す (同じ名前の複数の値も保つ)。 */
export function toParams(sp: SearchParams): URLSearchParams {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(sp)) {
    for (const v of Array.isArray(value) ? value : value === undefined ? [] : [value]) params.append(key, v);
  }
  return params;
}

/** 値が 1 つだけのときにその値を返す。無いか複数なら null。 */
export function single(params: URLSearchParams, name: string): string | null {
  return params.getAll(name).length === 1 ? params.get(name) : null;
}

/** 次のページの位置を外すキー。並べ替え・絞り込み・タブの差し替えに足す。 */
export const RESET_PAGE = { after: null } as const;

export type Sort<F extends string> = { field: F; direction: OrderDirection } | null;

/**
 * URL の `sort` (orderBy の field を小文字にした値) と `dir` (asc・desc) を読む。field の一覧に無い値と不正な向きは、
 * 既定の並び (null。orderBy を渡さない) にする。
 */
export function parseSort<F extends string>(params: URLSearchParams, fields: readonly F[]): Sort<F> {
  const key = single(params, "sort");
  const dir = single(params, "dir");
  const field = fields.find((f) => f.toLowerCase() === key);
  if (!field || (dir !== "asc" && dir !== "desc")) return null;
  return { field, direction: dir === "asc" ? "ASC" : "DESC" };
}

/** 見出しを押したときの次の並べ替え。同じ列は 昇順 → 降順 → 既定の並び、別の列は昇順。 */
export function nextSort<F extends string>(current: Sort<F>, field: F): Sort<F> {
  if (!current || current.field !== field) return { field, direction: "ASC" };
  return current.direction === "ASC" ? { field, direction: "DESC" } : null;
}

/** 並べ替えを差し替え、1 ページ目に戻した URL。 */
export function sortHref<F extends string>(pathname: string, params: URLSearchParams, sort: Sort<F>): string {
  return patchHref(pathname, params, {
    sort: sort ? sort.field.toLowerCase() : null,
    dir: sort ? sort.direction.toLowerCase() : null,
    ...RESET_PAGE,
  });
}

/** 1 ページの引数。`after` は URL の値をそのまま渡し、不正な値は API の検証に任せる。 */
export function pageArgs(params: URLSearchParams): { first: number; after: string | null } {
  return { first: PAGE_SIZE, after: single(params, "after") };
}

/** 次のページの URL。並べ替えと絞り込みを保ち、`after` だけを差し替える。 */
export function nextPageHref(pathname: string, params: URLSearchParams, endCursor: string): string {
  return patchHref(pathname, params, { after: endCursor });
}

/** 最初のページの URL。API は前のページへ辿らないので、前へはブラウザの戻る操作とこのリンクで戻る。 */
export function firstPageHref(pathname: string, params: URLSearchParams): string {
  return patchHref(pathname, params, RESET_PAGE);
}

/** URL の値のうち、許した値だけを残す (状況の絞り込み)。無ければ null (絞らない)。 */
export function parseEnumList<T extends string>(params: URLSearchParams, name: string, values: readonly T[]): T[] | null {
  const picked = params.getAll(name).filter((v): v is T => (values as readonly string[]).includes(v));
  return picked.length > 0 ? picked : null;
}

/** YYYY-MM-DD の形の値だけを日付として受ける。それ以外は null (絞らない)。 */
export function parseDate(params: URLSearchParams, name: string): string | null {
  const value = single(params, name);
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

/** コネクションの行。graphql-ruby の nodes は要素と配列の両方が null を許す型なので、null を除いた配列にする。 */
export function nodesOf<T>(connection: { nodes: readonly (T | null)[] | null }): T[] {
  return (connection.nodes ?? []).flatMap((node) => (node ? [node] : []));
}
