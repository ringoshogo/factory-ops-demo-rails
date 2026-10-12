/**
 * URL の差し替え (仕様 cycle-03 §4「URL」)。
 *
 * 絞り込み・タブ・ソートのリンクは、今の URL の他のパラメータを保ったまま、
 * 変える項目だけを差し替えて作る。この規則はここにだけ置く。
 */

/**
 * `params` に `patch` を当てた URL。`null` はそのキーを外し、値は置き換える
 * (同じ名前の複数の値は 1 つにまとまる)。クエリが空なら `?` を付けない。
 *
 * `useSearchParams()` の値は読み取り専用で、`set`・`delete` を呼ぶと例外になるので、
 * 受け取った `params` は変えず、複製を変える。
 */
export function patchHref(
  pathname: string,
  params: URLSearchParams,
  patch: Record<string, string | null>,
): string {
  const next = new URLSearchParams(params);
  for (const [key, value] of Object.entries(patch)) {
    if (value === null) next.delete(key);
    else next.set(key, value);
  }
  const query = next.toString();
  return query ? `${pathname}?${query}` : pathname;
}
