import type { LucideIcon } from "lucide-react";
import { cn } from "cn";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

/**
 * 一覧の絞り込みの並び。
 *
 * 絞り込みボタン・検索欄を左から並べ、一覧の件数を同じ行の右端に「N 件」で出す
 * (`data-testid="list-count"`)。`count` が null (API の失敗で一覧を出さない) なら件数を出さない。
 */
export function FilterBar({ count, children }: { count: React.ReactNode | null; children: React.ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {children}
      {count !== null && (
        <span data-testid="list-count" className="text-muted-foreground ml-auto text-[13px] tabular-nums">
          {count} 件
        </span>
      )}
    </div>
  );
}

/** 絞り込みボタンの見た目。値を選んでいるかで --filter-active-* に替える (共通部品 buttonVariants)。 */
export const filterButtonClass = (active: boolean) =>
  buttonVariants({ variant: active ? "filterActive" : "filter", size: "filter" });

/**
 * 絞り込みボタンの中身: アイコン + 項目名 + 値 (例「ステータス」「すべて」)。
 * アクセシブル名は表示どおり「ステータス すべて」で、`aria-label` を付けない (要素の並びで語が分かれる)。
 * 値を選んでいないときは値を文字 3 の色で出す。
 */
export function FilterButtonLabel({
  icon: Icon,
  label,
  value,
  active,
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  active: boolean;
}) {
  return (
    <>
      <Icon aria-hidden className={active ? "text-filter-active-border" : "text-muted-foreground"} />
      <span>{label}</span>
      <span className={cn("max-w-48 truncate font-normal", !active && "text-muted-foreground")}>{value}</span>
    </>
  );
}

/**
 * 検索欄 + 「検索」ボタン (品目)。文字を入れて送る形なので `<form method="get">` のまま。
 * 項目名を上に置かず、名前は `aria-label="検索"`、用途は placeholder で示す。高さは入力欄・二次ボタンの 36px。
 * 送るとクエリ全体が置き換わるので、保ちたいパラメータ (並べ替え) は `children` の
 * hidden input で持たせる。
 */
export function SearchForm({
  defaultValue,
  placeholder,
  children,
}: {
  defaultValue: string;
  placeholder: string;
  children?: React.ReactNode;
}) {
  return (
    <form method="get" className="flex w-full gap-2 sm:w-auto">
      <Input
        name="q"
        type="search"
        aria-label="検索"
        defaultValue={defaultValue}
        placeholder={placeholder}
        className="min-w-0 sm:w-72"
      />
      {children}
      <Button type="submit" variant="outline">
        検索
      </Button>
    </form>
  );
}
