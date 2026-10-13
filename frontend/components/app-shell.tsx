import { LogOut } from "lucide-react";
import { MainNav } from "@/components/main-nav";
import { MobileNav } from "@/components/mobile-nav";
import { PageFrame } from "@/components/page-frame";
import { ThemeToggle } from "@/components/theme-toggle";
import { Button } from "@/components/ui/button";
import { logout } from "@/lib/auth-actions";
import type { ViewerShellQuery } from "@/lib/graphql/generated";
import type { ThemeChoice } from "@/lib/theme";

type Viewer = ViewerShellQuery["viewer"] | null;

/** サイドバーの上端の自社の名前とユーザー。自社の名前は viewer.tenant から出す。 */
function Brand({ viewer }: { viewer: Viewer }) {
  return (
    <div className="text-sm leading-tight">
      <p data-testid="tenant-name" className="text-foreground font-semibold">
        {viewer?.tenant.name ?? "受発注・在庫・請求デモ"}
      </p>
      {viewer && (
        <p className="text-muted-foreground mt-0.5 text-xs">
          {viewer.name}・{viewer.role === "admin" ? "管理者" : "担当者"}
        </p>
      )}
    </div>
  );
}

function LogoutButton() {
  return (
    <form action={logout}>
      <Button type="submit" variant="ghost" size="sm" className="w-full justify-start">
        <LogOut aria-hidden />
        ログアウト
      </Button>
    </form>
  );
}

// 灰色の台の上に、本文を載せたパネルを 1 枚置く。幅 1024px 以上はサイドバーを台の上に常に出し、未満は上部バーの
// メニューのボタンからドロワーで開く
export function AppShell({ viewer, theme, children }: { viewer: Viewer; theme: ThemeChoice; children: React.ReactNode }) {
  const admin = viewer?.role === "admin";
  return (
    <div className="flex min-h-screen w-full">
      {/* サイドバーは台と同じ色で、右の境界線を持たない。選んでいる項目だけが浮く */}
      <aside className="bg-background sticky top-0 hidden h-screen w-62 shrink-0 flex-col gap-4 overflow-y-auto p-4 lg:flex">
        <div className="px-2.5 pt-1.5 pb-2">
          <Brand viewer={viewer} />
        </div>
        <MainNav admin={admin} />
        <div className="mt-auto flex flex-col gap-1">
          <LogoutButton />
          <ThemeToggle initial={theme} />
        </div>
      </aside>

      <PageFrame
        sidebar
        top={
          <header className="flex items-center gap-3 px-3 pt-2 lg:hidden">
            <MobileNav admin={admin} footer={<LogoutButton />} />
            <Brand viewer={viewer} />
            <div className="ml-auto">
              <ThemeToggle initial={theme} />
            </div>
          </header>
        }
      >
        <main className="w-full min-w-0 flex-1">{children}</main>
      </PageFrame>
    </div>
  );
}
