import { cn } from "cn";
import NextLink from "next/link";
import type { ComponentProps } from "react";

/**
 * アプリ内のリンク。**移動先を先読みしない**。
 *
 * どの画面も表示のたびに Rails を呼ぶので、先読みは表示しない画面の分まで Rails を呼ぶ。
 * 一覧の行のリンクを先読みすると、1 つの一覧を開くだけで行の数だけ詳細の問い合わせが出る。
 * `next/link` の直接の import は ESLint で禁じ、ここだけを通す。
 */
export function Link(props: ComponentProps<typeof NextLink>) {
  return <NextLink {...props} prefetch={false} />;
}

/**
 * 文中・見出し脇の文字のリンクの見た目。
 * アクセントの文字色 --link・下線なし・ホバーで --link-hover。
 * ボタンやタブの形をしたリンクは自分の見た目を持つので、これを通さない。
 */
export const TEXT_LINK = "text-link hover:text-link-hover no-underline";

export function TextLink({ className, ...props }: ComponentProps<typeof NextLink>) {
  return <Link {...props} className={cn(TEXT_LINK, className)} />;
}
