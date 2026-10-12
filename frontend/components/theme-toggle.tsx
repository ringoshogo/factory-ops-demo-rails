"use client";

import { Monitor, Moon, Sun } from "lucide-react";
import { useSyncExternalStore } from "react";
import { Button } from "@/components/ui/button";
import {
  nextTheme,
  THEME_COOKIE,
  THEME_LABELS,
  themeClass,
  themeFromClassList,
  type ThemeChoice,
} from "@/lib/theme";

const ICONS = { system: Monitor, light: Sun, dark: Moon } as const;

// 今の選択は `<html>` のクラスだけを正とする。サイドバーと上部バーに1つずつ
// 置くので、部品ごとに状態を持つと画面幅が変わったときに表示が食い違う
function subscribe(onChange: () => void) {
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
  return () => observer.disconnect();
}

const readChoice = () => themeFromClassList(document.documentElement.classList);

// Cookie はクライアントで書く。サーバーアクションで書くと現在のルートが
// 描き直され、ダッシュボードでは Rails への問い合わせが全部やり直しになる
export function ThemeToggle({ initial }: { initial: ThemeChoice }) {
  const choice = useSyncExternalStore(subscribe, readChoice, () => initial);
  const Icon = ICONS[choice];

  function cycle() {
    const next = nextTheme(readChoice());
    const root = document.documentElement;
    root.classList.remove("light", "dark");
    const cls = themeClass(next);
    if (cls) root.classList.add(cls);
    document.cookie =
      next === "system"
        ? `${THEME_COOKIE}=; Path=/; Max-Age=0; SameSite=Lax`
        : `${THEME_COOKIE}=${next}; Path=/; Max-Age=31536000; SameSite=Lax`;
  }

  return (
    <Button variant="ghost" size="sm" onClick={cycle} aria-label={`テーマ: ${THEME_LABELS[choice]}`}>
      <Icon aria-hidden className="size-4" />
      <span className="sr-only lg:not-sr-only">{THEME_LABELS[choice]}</span>
    </Button>
  );
}
