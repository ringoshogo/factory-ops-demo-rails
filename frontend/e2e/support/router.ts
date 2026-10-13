import type { Page } from "@playwright/test";

/**
 * Next の App Router が戻る・進むを受け付けられるまで待つ。`page.reload()` の直後に
 * `page.goBack()` / `page.goForward()` するときに呼ぶ。
 *
 * サーバーが描いた HTML は描き終わった時点で見えるので、見た目の検査はハイドレーション前に通る。
 * App Router は popstate の受け手を `useEffect` で登録する (next/dist/client/components/app-router.js
 * の `window.addEventListener('popstate', onPopState)`)。登録前に戻ると URL だけが変わり、画面は
 * 再読み込みした URL のまま残る。同じ effect が `history.pushState` を自前の関数に差し替えるので、
 * 差し替わったことを登録済みの合図にする。
 */
export async function waitForAppRouter(page: Page) {
  await page.waitForFunction(() => !Function.prototype.toString.call(window.history.pushState).includes("[native code]"));
}
