import { expect, test, type Page } from "@playwright/test";
import { SALES_ORDER_STATUS, SALES_ORDER_STATUS_ORDER } from "../lib/statuses";
import { login } from "./support/world";

// 一覧は 1 ページ (20 件) ずつ読み、並べ替えと件数はサーバーが行う。E2E の世界の品目は 22 件で、1 ページを超える
// (spec/scenarios/demo_world_spec.rb が件数を確かめる)

const rows = (page: Page) => page.getByTestId("list-row");

async function codes(page: Page): Promise<string[]> {
  return rows(page).locator("td:first-child").allInnerTexts();
}

async function names(page: Page): Promise<string[]> {
  return rows(page).locator("td:nth-child(2)").allInnerTexts();
}

/** 流用元の画面が名前と単位を並べる比べ方。DB の名前と単位の列の照合順序 ja-x-icu と同じ並びになる。 */
const byJapanese = new Intl.Collator("ja").compare;

test("品目の一覧を名前の昇順で 2 ページ目まで読むと、1 ページ目と重ならず、合わせて totalCount の件数になる", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/items?sort=name&dir=asc");
  const total = Number((await page.getByTestId("list-count").innerText()).replace(/[^0-9]/g, ""));
  expect(total).toBe(22);

  await expect(rows(page)).toHaveCount(20);
  const first = await codes(page);
  const firstNames = await names(page);

  await page.getByTestId("next-page").click();
  await expect(page).toHaveURL(/after=/);
  await expect(rows(page)).toHaveCount(total - 20);
  const second = await codes(page);
  const secondNames = await names(page);

  expect(first.filter((code) => second.includes(code))).toEqual([]);
  expect(new Set([...first, ...second]).size).toBe(total);
  // 2 ページを続けた名前の並びは、流用元の Intl.Collator("ja") で並べた並びと等しい。名前も重ならない
  expect([...firstNames, ...secondNames]).toEqual([...firstNames, ...secondNames].sort(byJapanese));
  expect(firstNames.filter((name) => secondNames.includes(name))).toEqual([]);
  // 2 ページ目に次は無く、最初のページへ戻れる
  await expect(page.getByTestId("next-page")).toHaveCount(0);
  await page.getByTestId("first-page").click();
  await expect(page).not.toHaveURL(/after=/);
  expect(await codes(page)).toEqual(first);
});

test("並べ替えの見出しを押すと、URL の sort・dir と並びが変わり、1 ページ目に戻る", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/items?sort=code&dir=asc");
  const ascending = await codes(page);
  await page.getByTestId("next-page").click();
  await expect(page).toHaveURL(/after=/);

  await page.getByRole("button", { name: "品目コード" }).click();
  await expect(page).toHaveURL(/sort=code&dir=desc/);
  await expect(page).not.toHaveURL(/after=/);
  await expect(page.getByRole("columnheader", { name: "品目コード" })).toHaveAttribute("aria-sort", "descending");
  const descending = await codes(page);
  expect(descending).toHaveLength(20);
  // 降順の 1 ページ目は、昇順の全件の後ろから 20 件を逆に並べたもの。昇順の 1 ページ目の先頭は降順の 1 ページ目に無い
  expect(descending[0] > ascending[0]).toBe(true);
  expect(descending).not.toContain(ascending[0]);
  expect([...descending].sort().reverse()).toEqual(descending);

  await page.getByRole("button", { name: "品目名" }).click();
  await expect(page).toHaveURL(/sort=name&dir=asc/);
});

/** 一覧の n 列目 (1 から) のセルの文字。 */
async function column(page: Page, n: number): Promise<string[]> {
  return rows(page).locator(`td:nth-child(${n})`).allInnerTexts();
}

/** 続けて同じ値が並ぶところを 1 つにまとめる。 */
const runs = (values: readonly string[]) => values.filter((v, i) => i === 0 || values[i - 1] !== v);

/** 一覧の n 列目 (1 から) のセルの文字がちょうど text の行のうち、最初の行の詳細へのリンク。 */
const rowLink = (page: Page, n: number, text: string) =>
  rows(page)
    .filter({ has: page.locator(`td:nth-child(${n})`, { hasText: new RegExp(`^${text}$`) }) })
    .first()
    .getByRole("link");

/** 伝票の詳細へのリンクの、道の末尾の ID。 */
async function idOf(link: ReturnType<Page["getByRole"]>): Promise<string> {
  return (await link.getAttribute("href"))!.split("/").at(-1)!;
}

// 合計の無い受注の欄の文字。品番照合待ちの受注は「照合待ち」、照合待ちのまま取り消した受注は「取消」
const NO_TOTAL = ["照合待ち", "取消"];

test("受注一覧を取引先の名前と受注合計で並べ、合計の無い受注は末尾に並び、照合待ちの受注は一覧・詳細・かんばんのどれでも「照合待ち」と出る", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/sales-orders");

  // 世界の受注の得意先は 2 社で、名前の先頭の漢字のコードポイントの順と音読みの順が逆になる組。
  // 同じ得意先の受注がまとまり、まとまりの順は流用元の Intl.Collator("ja") で並べた順で、降順で逆になる。
  // 絞り込みにも「取引先」のボタンがあるので、見出しの中から探す
  const customer = page.getByRole("columnheader", { name: "取引先" }).getByRole("button");
  await expect(customer).toBeVisible();
  await customer.click();
  await expect(page).toHaveURL(/sort=customer_name&dir=asc/);
  await expect(page.getByRole("columnheader", { name: "取引先" })).toHaveAttribute("aria-sort", "ascending");
  const ascending = runs(await column(page, 2));
  expect(ascending).toHaveLength(2);
  expect(ascending).toEqual([...ascending].sort(byJapanese));
  await customer.click();
  await expect(page).toHaveURL(/sort=customer_name&dir=desc/);
  expect(runs(await column(page, 2))).toEqual([...ascending].reverse());

  await page.getByRole("columnheader", { name: "受注合計" }).getByRole("button").click();
  await expect(page).toHaveURL(/sort=total_amount&dir=asc/);
  const totals = await column(page, 6);
  const noTotalFrom = totals.findIndex((t) => NO_TOTAL.includes(t));
  expect(noTotalFrom).toBeGreaterThan(0);
  expect(totals.slice(noTotalFrom).every((t) => NO_TOTAL.includes(t))).toBe(true);
  // 末尾には、照合待ちの受注も、照合待ちのまま取り消した受注も並ぶ
  expect(new Set(totals.slice(noTotalFrom))).toEqual(new Set(NO_TOTAL));
  const amounts = totals.slice(0, noTotalFrom).map((t) => BigInt(t.replace(/[^0-9]/g, "")));
  expect(amounts).toEqual([...amounts].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0)));

  // 一覧で「照合待ち」と出た受注を、詳細とかんばんのカードでも見る。末尾の行は取り消した受注のことがあるので、文字で選ぶ
  const link = rowLink(page, 6, "照合待ち");
  const orderId = await idOf(link);
  await link.click();
  await expect(page.getByTestId("order-total")).toHaveText("照合待ち");
  await page.goto("/supplier/dashboard");
  await expect(page.locator(`[data-testid="kanban-card"][data-order-id="${orderId}"]`).getByTestId("card-total")).toHaveText("照合待ち");
});

test("照合待ちのまま取り消した受注と発注は、取消済のタブ・詳細・かんばんの合計の欄に「取消」と、詳細の明細の行に取消の文言と出る", async ({ browser }, testInfo) => {
  const page = await (await browser.newContext()).newPage();
  await login(page, testInfo, "supplier_admin");
  // 対照：取り消していない品番照合待ちの受注の明細の行には、待ちの文言が出る
  await page.goto("/supplier/sales-orders?tab=open");
  await rowLink(page, 6, "照合待ち").click();
  await expect(page.getByTestId("order-line").filter({ hasText: "品番照合待ち" })).not.toHaveCount(0);
  await expect(page.getByTestId("order-line").getByText("品番照合待ち", { exact: true }).first()).toHaveClass(/text-caution/);

  await page.goto("/supplier/sales-orders?tab=cancelled");
  const totals = await column(page, 6);
  expect(totals).toContain("取消");
  // 対照：単価の決まった明細だけの受注は、取り消しても合計を金額で出す
  expect(totals.some((t) => t.endsWith(" 円"))).toBe(true);

  const link = rowLink(page, 6, "取消");
  const orderId = await idOf(link);
  await link.click();
  await expect(page.getByTestId("order-total")).toHaveText("取消");
  // 取り消した受注はもう照合を待たないので、明細の行も待ちの文言の代わりに取消の文言を出す
  await expect(page.getByTestId("order-line").filter({ hasText: "品番未照合（取消）" })).not.toHaveCount(0);
  await expect(page.getByTestId("order-line").filter({ hasText: "品番照合待ち" })).toHaveCount(0);
  // 待っていないものを注意の色で出さず、同じ行の得意先品番と同じ色で出す
  const cancelledLine = page.getByTestId("order-line").getByText("品番未照合（取消）", { exact: true }).first();
  await expect(cancelledLine).not.toHaveClass(/text-caution/);
  await expect(cancelledLine).toHaveClass(/text-muted-foreground/);
  // かんばんの取消済の列にも、同じ受注のカードが「取消」と出る
  await page.goto("/supplier/dashboard");
  await expect(page.locator(`[data-testid="kanban-card"][data-order-id="${orderId}"]`).getByTestId("card-total")).toHaveText("取消");

  // 発注側の一覧では、受注側により取り消した発注の合計の欄に「取消」と出る。テナントをまたいで受注と発注の ID は
  // 対応づけられないので、詳細は一覧の行から開く
  const buyer = await (await browser.newContext()).newPage();
  await login(buyer, testInfo, "granted_buyer_admin");
  // 対照：取り消していない受注確定の前の発注の明細の行には、待ちの文言が出る
  await buyer.goto("/buyer/purchase-orders?tab=open");
  await rowLink(buyer, 7, "確定待ち").click();
  await expect(buyer.getByTestId("order-line").filter({ hasText: "受注側の確定待ち" })).not.toHaveCount(0);

  await buyer.goto("/buyer/purchase-orders?tab=cancelled");
  const purchaseTotals = await column(buyer, 7);
  expect(purchaseTotals).toContain("取消");
  expect(purchaseTotals.some((t) => t.endsWith(" 円"))).toBe(true);
  expect(purchaseTotals).not.toContain("確定待ち");
  await rowLink(buyer, 7, "取消").click();
  await expect(buyer.getByTestId("order-line").filter({ hasText: "未確定（取消）" })).not.toHaveCount(0);
  await expect(buyer.getByTestId("order-line").filter({ hasText: "受注側の確定待ち" })).toHaveCount(0);
});

/** URL の sort と dir。 */
function sortOf(page: Page): (string | null)[] {
  const params = new URL(page.url()).searchParams;
  return [params.get("sort"), params.get("dir")];
}

test("受注一覧の見出しを Shift を押して押すと 2 つ目の並べる列を足し、見出しに番号が出て、状況の同じ行が取引先の名前の降順に並ぶ", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/sales-orders");
  const statusHead = page.getByRole("columnheader", { name: "状況" });
  const customerHead = page.getByRole("columnheader", { name: "取引先" });
  const customer = customerHead.getByRole("button");

  // ブラウザは Shift を押したクリックで、前に押したところからの文字を選ぶことがある。見出しは Shift を押した mousedown の
  // 既定の動きだけを止める。Chromium はボタンの上の Shift を押したクリックで文字を選ばず、選ばれた文字では止めたかを確かめられないので、
  // document まで届いた mousedown が既定の動きを止められたかで確かめる
  await page.evaluate(() =>
    document.addEventListener("mousedown", (e) => document.body.setAttribute("data-prevented", String(e.defaultPrevented))),
  );
  await statusHead.getByRole("button").click();
  await expect(page).toHaveURL(/sort=status&dir=asc/);
  // 対照：Shift を押さないクリックは止めない (ボタンにフォーカスが移る)
  await expect(page.locator("body")).toHaveAttribute("data-prevented", "false");
  await customer.click({ modifiers: ["Shift"] });
  await expect(page.locator("body")).toHaveAttribute("data-prevented", "true");
  await expect.poll(() => sortOf(page)).toEqual(["status,customer_name", "asc,asc"]);
  expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("");
  await customer.click({ modifiers: ["Shift"] });
  await expect.poll(() => sortOf(page)).toEqual(["status,customer_name", "asc,desc"]);

  // 番号は並びの順に出る。aria-sort は 1 つ目の列にだけ付け、2 つ目の列は見えない文字で順番と向きを添え、ボタンの名前は変えない
  await expect(statusHead.locator("[data-sort-rank]")).toHaveText("1");
  await expect(customerHead.locator("[data-sort-rank]")).toHaveText("2");
  await expect(statusHead).toHaveAttribute("aria-sort", "ascending");
  await expect(customerHead).not.toHaveAttribute("aria-sort");
  await expect(customerHead).toContainText("並べ替え 2 番目・降順");
  await expect(customer).toHaveAccessibleName("取引先");

  // 1 ページ目の行は状況の業務の進み順に並び、状況の同じ行は取引先の名前の降順に並ぶ。E2E の世界の受注の取引先は 2 社で、
  // 降順は主キーの順とも食い違うので、thenBy が効かなければ並びが崩れる。受注日は世界のどの受注も同じで、確かめにならない
  const labels = SALES_ORDER_STATUS_ORDER.map((s) => SALES_ORDER_STATUS[s].label);
  const statuses = (await column(page, 5)).map((text) => labels.findIndex((label) => text.startsWith(label)));
  const customers = await column(page, 2);
  expect(statuses).not.toContain(-1);
  expect(statuses).toEqual([...statuses].sort((a, b) => a - b));
  const pairs = statuses.slice(1).map((s, i) => ({ same: s === statuses[i], before: customers[i], after: customers[i + 1] }));
  expect(pairs.filter((p) => p.same && byJapanese(p.before, p.after) < 0)).toEqual([]);
  // 対照：状況の同じ行に 2 社が並ぶまとまりがある
  expect(pairs.some((p) => p.same && p.before !== p.after)).toBe(true);

  // Shift を押した Enter も、2 つ目の列の向きを進める (降順の次は並びから外す)
  await customer.focus();
  await customer.press("Shift+Enter");
  await expect.poll(() => sortOf(page)).toEqual(["status", "asc"]);
  await expect(page.locator("[data-sort-rank]")).toHaveCount(0);
});

test("出荷依頼の受注番号の見出しを押すと受注番号の順に並び、品目の単価の見出しを Shift を押して押すと、単位のまとまりが流用元の順に並び、単位の同じ品目が単価の順に並ぶ", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/shipment-requests");
  // 受注番号は「出荷可能」のイベントで写した値で並び、表示は受注の値である。写しが受注と食い違えば並びが崩れる
  await page.getByRole("columnheader", { name: "受注番号" }).getByRole("button").click();
  await expect.poll(() => sortOf(page)).toEqual(["order_no", "asc"]);
  await expect(page.getByRole("columnheader", { name: "受注番号" })).toHaveAttribute("aria-sort", "ascending");
  const orderNos = await column(page, 1);
  // 伝票番号は桁をそろえた ASCII の文字列なので、文字列の順が番号の順になる
  expect(orderNos).toEqual([...orderNos].sort());
  // 対照：並びを確かめられるだけの出荷依頼がある
  expect(new Set(orderNos).size).toBeGreaterThan(1);

  await page.goto("/supplier/items?sort=unit&dir=asc");
  await page.getByRole("columnheader", { name: "単価" }).getByRole("button").click({ modifiers: ["Shift"] });
  await expect.poll(() => sortOf(page)).toEqual(["unit,unit_price", "asc,asc"]);
  await expect(page.getByRole("columnheader", { name: "単価" }).locator("[data-sort-rank]")).toHaveText("2");

  // 単位の同じ品目はひとまとまりに並び、まとまりの中は単価の昇順に並ぶ。E2E の世界の品目は単位が「個」の品目が多く、
  // 単価は作った順と食い違うので、thenBy が効かなければ並びが崩れる
  const units = await column(page, 3);
  const prices = (await column(page, 4)).map((text) => Number(text.replace(/[^0-9]/g, "")));
  expect(runs(units)).toEqual([...new Set(units)]);
  // 単位のまとまりは、流用元と同じ比べ方の順に並ぶ。DB の既定の照合順序 (en_US.utf8) では、コードポイントの順に本が箱より先になる。
  // 対照：1 ページ目に、並びを比べられるだけの単位がある
  expect(runs(units).length).toBeGreaterThanOrEqual(3);
  expect(runs(units)).toEqual([...runs(units)].sort(byJapanese));
  const pairs = units.slice(1).map((u, i) => ({ same: u === units[i], before: prices[i], after: prices[i + 1] }));
  expect(pairs.filter((p) => p.same && p.before > p.after)).toEqual([]);
  // 対照：単位の同じ品目に、単価の違う組がある
  expect(pairs.some((p) => p.same && p.before !== p.after)).toBe(true);
});

test("在庫の画面で品目名の一部を検索すると、URL の q が変わって当たる在庫だけが件数と一緒に出て、品目コードの並べ替えと安全在庫の絞り込みを重ねられる", async ({ page }, testInfo) => {
  await login(page, testInfo, "supplier_admin");
  await page.goto("/supplier/stocks");
  // 対照：検索の前は、品目名に「シール」を含まない在庫も出る
  await expect(rows(page)).not.toHaveCount(0);
  const before = await names(page);
  expect(before.some((name) => !name.includes("シール"))).toBe(true);

  // E2E の世界で品目名に「シール」を含む在庫は、オイルシール (ITM-006) と長い名前の品目 (ITM-030) の 2 つ
  const search = page.getByRole("searchbox", { name: "検索" });
  await expect(search).toBeVisible();
  await search.fill("シール");
  await search.press("Enter");
  await expect.poll(() => new URL(page.url()).searchParams.get("q")).toBe("シール");
  await expect(rows(page)).toHaveCount(2);
  await expect(page.getByTestId("list-count")).toHaveText("2 件");
  expect((await names(page)).every((name) => name.includes("シール"))).toBe(true);

  await page.getByRole("columnheader", { name: "品目コード" }).getByRole("button").click();
  await expect(page).toHaveURL(/sort=item_code&dir=asc/);
  expect(new URL(page.url()).searchParams.get("q")).toBe("シール");
  expect(await codes(page)).toEqual(["ITM-006", "ITM-030"]);
  await page.getByRole("columnheader", { name: "品目コード" }).getByRole("button").click();
  await expect(page).toHaveURL(/sort=item_code&dir=desc/);
  expect(await codes(page)).toEqual(["ITM-030", "ITM-006"]);

  // 初期在庫が安全在庫を下回るのは ITM-006 だけで、検索と両方に当たる
  await page.getByRole("button", { name: "在庫 すべて" }).click();
  await page.getByRole("menuitemradio", { name: "安全在庫を下回るものだけ" }).click();
  await expect(page).toHaveURL(/below=1/);
  expect(new URL(page.url()).searchParams.get("q")).toBe("シール");
  await expect(rows(page)).toHaveCount(1);
  await expect(page.getByTestId("list-count")).toHaveText("1 件");
  expect(await codes(page)).toEqual(["ITM-006"]);
});
