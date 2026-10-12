import { SiteFooter } from "@/components/site-footer";

/**
 * 全画面に共通の枠。台の上にパネルを 1 枚置き、その下端に架空表記を出す。サイドバーの有無にかかわらず、どの画面も
 * これを通す (ログインの画面・業務の画面・見つからない画面)。枠ごとに組み合わせを書くと、枠を足したときに架空表記が抜ける。
 * `top` はパネルより上の台に置くもの (狭い幅のメニューの上部バー・テーマの切り替え)。
 *
 * パネルは台の内側 8px に置き、`sidebar` の枠では、サイドバーの出る幅 (lg 以上) で左を 0 にする
 * (サイドバーの内側の余白が間を作る)。かんばんと表は自分の容器の中で横にスクロールするので、パネルに `min-w-0` を付ける。
 */
export function PageFrame({
  top,
  sidebar = false,
  children,
}: {
  top?: React.ReactNode;
  sidebar?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen min-w-0 flex-1 flex-col">
      {top}
      <div
        data-slot="panel"
        className={`${sidebar ? "lg:ml-0" : ""} bg-card text-card-foreground shadow-panel rounded-panel m-2 flex min-w-0 flex-1 flex-col gap-5 px-4 py-5 lg:px-10 lg:pt-7 lg:pb-10`}
      >
        {children}
        <SiteFooter />
      </div>
    </div>
  );
}
