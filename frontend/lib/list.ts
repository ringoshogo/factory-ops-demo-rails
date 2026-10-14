import type { OrderDirection } from "@/lib/graphql/generated";
import { patchHref } from "@/lib/query";

/**
 * 一覧の画面の URL を、GraphQL の一覧の引数 (first・after・orderBy・thenBy・filter) に写す。
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

export type SortKey<F extends string> = { field: F; direction: OrderDirection };

/** 並べる列の並び。1 つ目の列から順に並べる。空の並びは既定の並び (orderBy も thenBy も渡さない)。 */
export type Sort<F extends string> = readonly SortKey<F>[];

/** 並べる列の数の上限。API の orderBy と thenBy を合わせた上限と同じ値にする (spec/graphql/sort_arguments_spec.rb が確かめる)。 */
export const MAX_SORTS = 3;

/**
 * URL の `sort` (orderBy の field を小文字にした値) と `dir` (asc・desc) を、列の順にコンマでつないだ同じ長さの並びとして読む
 * (`sort=customer_name,order_date&dir=asc,desc`)。列が 1 つの URL は、コンマの無い値 (`sort=due_date&dir=asc`) になる。
 * 並びの長さが違う、field の一覧に無い値か不正な向きを含む、同じ列が 2 回ある、MAX_SORTS を超える、のどれかは、
 * 既定の並び (空の並び) にする。
 */
export function parseSort<F extends string>(params: URLSearchParams, fields: readonly F[]): Sort<F> {
  const keys = single(params, "sort")?.split(",") ?? [];
  const dirs = single(params, "dir")?.split(",") ?? [];
  if (keys.length !== dirs.length || keys.length > MAX_SORTS || new Set(keys).size !== keys.length) return [];
  const sort = keys.map((key, i) => {
    const field = fields.find((f) => f.toLowerCase() === key);
    const dir = dirs[i];
    return field && (dir === "asc" || dir === "desc") ? { field, direction: dir === "asc" ? "ASC" : "DESC" } as const : null;
  });
  return sort.every((s) => s !== null) ? sort : [];
}

/** 並びを一覧の引数に写す。1 つ目の列を orderBy、2 つ目からを thenBy にする。 */
export function sortArgs<F extends string>(sort: Sort<F>): { orderBy: SortKey<F> | null; thenBy: SortKey<F>[] | null } {
  return { orderBy: sort[0] ?? null, thenBy: sort.length > 1 ? sort.slice(1) : null };
}

/**
 * 見出しを押したときの次の並び。Shift を押さなければ、その列 1 つの並びにする (並びがその列 1 つなら 昇順 → 降順 → 既定の並び の
 * 順に進め、それ以外は昇順)。Shift を押せば、並びに無い列は昇順で後ろに足し、並びにある列はその列の向きだけを 昇順 → 降順 → 並びから外す の
 * 順に進め、ほかの列の順と向きを保つ。並びが MAX_SORTS のときに、並びに無い列を Shift を押して押しても変えない。
 */
export function nextSort<F extends string>(current: Sort<F>, field: F, shift: boolean): Sort<F> {
  const index = current.findIndex((s) => s.field === field);
  const at = current[index];
  if (!shift) {
    if (current.length !== 1 || !at) return [{ field, direction: "ASC" }];
    return at.direction === "ASC" ? [{ field, direction: "DESC" }] : [];
  }
  if (!at) return current.length < MAX_SORTS ? [...current, { field, direction: "ASC" }] : current;
  return at.direction === "ASC"
    ? current.map((s, i) => (i === index ? { field, direction: "DESC" } : s))
    : current.filter((_, i) => i !== index);
}

/** 見出しに出す、何番目の並べる列か (1 から)。並びが 1 つ以下か、並びに無い列は null で、番号を出さない。 */
export function sortRank<F extends string>(sort: Sort<F>, field: F): number | null {
  const index = sort.findIndex((s) => s.field === field);
  return sort.length > 1 && index >= 0 ? index + 1 : null;
}

/** 並びの URL の値。既定の並びは null (値を外す)。 */
export function sortParams<F extends string>(sort: Sort<F>): { sort: string | null; dir: string | null } {
  if (sort.length === 0) return { sort: null, dir: null };
  return {
    sort: sort.map((s) => s.field.toLowerCase()).join(","),
    dir: sort.map((s) => s.direction.toLowerCase()).join(","),
  };
}

/** 並べ替えを差し替え、1 ページ目に戻した URL。 */
export function sortHref<F extends string>(pathname: string, params: URLSearchParams, sort: Sort<F>): string {
  return patchHref(pathname, params, { ...sortParams(sort), ...RESET_PAGE });
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
