import { cn } from "cn";
import NextLink from "next/link";
import type { ComponentProps } from "react";

/**
 * アプリ内のリンク。**移動先を先読みしない** (正本 N-15)。
 *
 * どの画面も表示のたびに API を呼ぶ動的ページで、先読みは1リンクにつき2件の
 * 要求を出し、サーバーでは API も呼ぶ。エッジのレート制限 (1クライアント 50req/10s) は
 * demo.hayatec.dev にもかかり、受注一覧の行リンクを先読みすると初回表示だけで上限に近づいた。
 * `next/link` の直接の import は ESLint で禁じ、ここだけを通す。
 */
export function Link(props: ComponentProps<typeof NextLink>) {
  return <NextLink {...props} prefetch={false} />;
}

/**
 * 文中・見出し脇の文字のリンクの見た目 (仕様 cycle-03 §3 共通部品「リンク」)。
 * アクセントの文字色 --link・下線なし・ホバーで --link-hover。
 * ボタンやタブの形をしたリンクは自分の見た目を持つので、これを通さない。
 */
export const TEXT_LINK = "text-link hover:text-link-hover no-underline";

export function TextLink({ className, ...props }: ComponentProps<typeof NextLink>) {
  return <Link {...props} className={cn(TEXT_LINK, className)} />;
}
