"use client";

import { Dialog as DialogPrimitive } from "@base-ui/react/dialog";
import { Menu, XIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { MainNav } from "@/components/main-nav";
import { Button } from "@/components/ui/button";
import { DialogOverlay, DialogPortal } from "@/components/ui/dialog";

/**
 * 狭い画面のドロワー。フォーカスの閉じ込め・Esc・外側の押下・閉じたときのフォーカスの復帰は Base UI の Dialog に任せる。
 * `footer` はドロワーの下端に置くもの (ログアウト)。
 */
export function MobileNav({ admin, footer }: { admin: boolean; footer?: React.ReactNode }) {
  const [open, setOpen] = useState(false);

  // 開いたまま広い画面へ広げたら閉じる (サイドバーと同じメニューが 2 つ見えるのを防ぐ)。
  // 1024px は app-shell の `lg:` と同じ境目
  useEffect(() => {
    const wide = window.matchMedia("(min-width: 1024px)");
    const close = () => wide.matches && setOpen(false);
    wide.addEventListener("change", close);
    return () => wide.removeEventListener("change", close);
  }, []);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={setOpen}>
      <DialogPrimitive.Trigger render={<Button variant="ghost" size="icon-sm" />}>
        <Menu aria-hidden className="size-5" />
        <span className="sr-only">メニューを開く</span>
      </DialogPrimitive.Trigger>
      <DialogPortal>
        <DialogOverlay />
        <DialogPrimitive.Popup
          aria-label="メニュー"
          className="bg-background shadow-popup fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col gap-6 overflow-y-auto p-4 outline-none duration-150 data-open:animate-in data-open:slide-in-from-left data-closed:animate-out data-closed:slide-out-to-left"
        >
          <div className="flex items-center justify-end">
            <DialogPrimitive.Close render={<Button variant="ghost" size="icon-sm" />}>
              <XIcon aria-hidden />
              <span className="sr-only">メニューを閉じる</span>
            </DialogPrimitive.Close>
          </div>
          <MainNav admin={admin} onNavigate={() => setOpen(false)} />
          {footer && <div className="mt-auto">{footer}</div>}
        </DialogPrimitive.Popup>
      </DialogPortal>
    </DialogPrimitive.Root>
  );
}
