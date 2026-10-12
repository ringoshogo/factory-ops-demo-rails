import { TextLink } from "@/components/app-link";
import { EntryCard } from "@/components/entry-shell";

/**
 * 見つからない画面の本文。画面群の中とそれ以外の URL の両方で使う。ID で引いて返らなかった伝票は、無いのか
 * 見えないのか (他社のもの) を言い分けない (docs/architecture/graphql-schema.md「ID と `node`」)。
 */
export function NotFoundMessage({ href, label }: { href: string; label: string }) {
  return (
    <EntryCard data-testid="not-found" className="space-y-3">
      <h1>ページが見つかりません</h1>
      <p className="text-muted-foreground text-sm">URL が正しいかを確かめてください。</p>
      <TextLink href={href} className="text-sm">
        {label}
      </TextLink>
    </EntryCard>
  );
}
