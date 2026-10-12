"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { TextLink } from "@/components/app-link";
import { firstPageHref, nextPageHref } from "@/lib/list";

/**
 * 一覧の下のページの送り。API は前のページへ辿らないので、前へはブラウザの戻る操作と「最初のページ」で戻る。
 * 1 ページ目では「最初のページ」を出さず、次のページが無ければ「次のページ」を出さない。
 */
export function Pagination({ pageInfo }: { pageInfo: { hasNextPage: boolean; endCursor: string | null } }) {
  const pathname = usePathname();
  const params = useSearchParams();
  const onFirstPage = !params.has("after");
  if (onFirstPage && !pageInfo.hasNextPage) return null;

  return (
    <nav aria-label="ページ" className="flex items-center justify-end gap-4 text-sm">
      {!onFirstPage && (
        <TextLink href={firstPageHref(pathname, params)} data-testid="first-page">
          最初のページ
        </TextLink>
      )}
      {pageInfo.hasNextPage && pageInfo.endCursor && (
        <TextLink href={nextPageHref(pathname, params, pageInfo.endCursor)} data-testid="next-page">
          次のページ
        </TextLink>
      )}
    </nav>
  );
}
