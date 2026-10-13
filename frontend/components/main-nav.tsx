"use client";

import {
  Boxes,
  Building2,
  ClipboardList,
  FileClock,
  FileInput,
  FileText,
  Handshake,
  LayoutDashboard,
  Link2,
  Package,
  Receipt,
  ScrollText,
  Settings,
  ShoppingCart,
  Truck,
  type LucideIcon,
} from "lucide-react";
import { usePathname } from "next/navigation";
import { useId } from "react";
import { Link } from "@/components/app-link";

type NavItem = { label: string; href: string; Icon: LucideIcon; adminOnly?: boolean };

/**
 * サイドバーのグループ。テナントは発注側と受注側のどちらにもなりうるので、受注側と発注側の両方のグループを常に出し、
 * 同じテナントの中でグループを移って視点を切り替える。グループの名前は見出しの要素にしない (画面の見出しと紛れる)。
 */
export const NAV_GROUPS: { label: string; items: NavItem[] }[] = [
  {
    label: "受注側",
    items: [
      { label: "ダッシュボード", href: "/supplier/dashboard", Icon: LayoutDashboard },
      { label: "受注", href: "/supplier/sales-orders", Icon: ClipboardList },
      { label: "品番の対応表", href: "/supplier/part-mappings", Icon: Link2 },
      { label: "在庫", href: "/supplier/stocks", Icon: Boxes },
      { label: "出荷依頼", href: "/supplier/shipment-requests", Icon: Truck },
      { label: "品目", href: "/supplier/items", Icon: Package },
      { label: "取引関係", href: "/supplier/partnerships", Icon: Handshake },
      { label: "請求の締め", href: "/supplier/billing", Icon: Receipt },
      { label: "請求書", href: "/supplier/invoices", Icon: FileText },
      { label: "取り込み", href: "/supplier/imports", Icon: FileInput },
    ],
  },
  {
    label: "発注側",
    items: [
      { label: "取引先とカタログ", href: "/buyer/suppliers", Icon: Building2 },
      { label: "発注", href: "/buyer/purchase-orders", Icon: ShoppingCart },
      { label: "受領請求書", href: "/buyer/received-invoices", Icon: ScrollText },
    ],
  },
  {
    label: "自社",
    items: [
      { label: "自社の情報", href: "/settings", Icon: Settings },
      { label: "監査ログ", href: "/audit-logs", Icon: FileClock, adminOnly: true },
    ],
  },
];

/** 詳細と登録の画面 (`/supplier/sales-orders/...`) も一覧の項目を現在地とする。 */
function isCurrent(pathname: string, href: string): boolean {
  return pathname === href || pathname.startsWith(`${href}/`);
}

/**
 * サイドバーとドロワーが同じものを描く (2 か所に書かない)。`onNavigate` はドロワーが項目を選んだときに閉じるために使う。
 * `admin` でなければ、admin だけが読める画面 (監査ログ) を出さない。
 */
export function MainNav({ admin, onNavigate }: { admin: boolean; onNavigate?: () => void }) {
  const pathname = usePathname();
  // サイドバー (狭い画面では隠れる) とドロワーが同時に DOM にあっても id がぶつからないように
  const idBase = useId();

  return (
    <nav aria-label="メインメニュー" className="flex flex-col gap-4">
      {NAV_GROUPS.map((group, g) => {
        const labelId = `${idBase}-group-${g}`;
        return (
          <div key={group.label} className="flex flex-col gap-1">
            <p id={labelId} className="text-muted-foreground px-2.5 text-xs font-medium">
              {group.label}
            </p>
            <ul aria-labelledby={labelId} className="flex flex-col gap-0.5">
              {group.items
                .filter((item) => admin || !item.adminOnly)
                .map(({ label, href, Icon }) => {
                  const current = isCurrent(pathname, href);
                  // 選んでいる項目だけが面と影で台から浮き、アイコンがアクセントの文字色になる。ほかの項目は台に溶け込む
                  return (
                    <li key={href}>
                      <Link
                        href={href}
                        onClick={onNavigate}
                        aria-current={current ? "page" : undefined}
                        className={`rounded-control flex h-9 items-center gap-3 px-2.5 font-medium ${
                          current
                            ? "bg-sidebar-selected shadow-panel text-foreground"
                            : "text-foreground-2 hover:bg-foreground/5"
                        }`}
                      >
                        <Icon
                          aria-hidden
                          className={`size-4.5 shrink-0 ${current ? "text-link" : "text-muted-foreground"}`}
                        />
                        {label}
                      </Link>
                    </li>
                  );
                })}
            </ul>
          </div>
        );
      })}
    </nav>
  );
}
