"use client"

/*
 * 表: 外枠・縦罫線・縞を持たない。見出しの下は --divider-strong、
 * 行の間は --divider-subtle、ホバー行は --row-hover。行の高さ 52px・左右 12px・端の列は 0。
 *
 * 列のそろえはここだけで決める。数値の列 (`numeric`) だけ
 * 見出しもセルも右寄せにし、ほかの列 (操作を含む) は左寄せのまま。画面側で `text-right` を書かない。
 */

import * as React from "react"
import { cn } from "cn"

function Table({ className, ...props }: React.ComponentProps<"table">) {
  return (
    <div
      data-slot="table-container"
      className="relative w-full overflow-x-auto"
    >
      <table
        data-slot="table"
        className={cn("w-full caption-bottom text-sm", className)}
        {...props}
      />
    </div>
  )
}

function TableHeader({ className, ...props }: React.ComponentProps<"thead">) {
  return (
    <thead
      data-slot="table-header"
      className={className}
      {...props}
    />
  )
}

function TableBody({ className, ...props }: React.ComponentProps<"tbody">) {
  return (
    <tbody
      data-slot="table-body"
      className={className}
      {...props}
    />
  )
}

function TableFooter({ className, ...props }: React.ComponentProps<"tfoot">) {
  return (
    <tfoot
      data-slot="table-footer"
      className={cn(
        "border-t bg-muted/50 font-medium [&>tr]:last:border-b-0",
        className
      )}
      {...props}
    />
  )
}

function TableRow({ className, ...props }: React.ComponentProps<"tr">) {
  return (
    <tr
      data-slot="table-row"
      className={cn(
        // ホバー行の面はセルに塗る (縞は付けない)
        "[&:hover>td]:bg-row-hover has-aria-expanded:[&>td]:bg-row-hover data-[state=selected]:[&>td]:bg-muted",
        className
      )}
      {...props}
    />
  )
}

/**
 * ソートの矢印 (見出しのボタンの中で、文字の右に置く)。大きさ 14px・文字との間 4px。
 * ソートできる数値の列のセルは、この幅 (18px) を右に空けて、数字の右端を見出しの**文字**の右端にそろえる。
 *
 * 複数の列で並べるときは、矢印の右に何番目の並べる列かの番号 (`rank`。幅 8px・矢印との間 4px) を置く。番号の出る数値の列の
 * セルは、矢印の 18px に番号の 12px を足した幅を右に空ける。番号を矢印に重ねて幅を取らない形にすると、最後の列の番号が表の右端からはみ出す
 */
export const SORT_ICON = { size: "size-3.5", gap: "gap-1", rank: "w-2 text-[10px] leading-none tabular-nums" } as const
const SORT_ICON_SLOT = "pr-7.5 last:pr-4.5"
const SORT_RANK_SLOT = "pr-10.5 last:pr-7.5"

function TableHead({
  className,
  numeric = false,
  ...props
}: React.ComponentProps<"th"> & { numeric?: boolean }) {
  return (
    <th
      data-slot="table-head"
      className={cn(
        "border-divider-strong border-b px-3 pb-2.5 text-left align-middle text-[13px] font-medium whitespace-nowrap text-muted-foreground first:pl-0 last:pr-0 [&:has([role=checkbox])]:pr-0",
        numeric && "text-right",
        className
      )}
      {...props}
    />
  )
}

/**
 * 省略できる列の最小幅。`true` は 96px。`"wide"` は 1280px 以上で 224px を取り、ふつうの長さの名前は省略しない
 * (表は足りない幅を省略できる列すべてに割り振るので、他の列に詰めを受け持たせたい列に使う)。
 */
type Truncate = boolean | "wide"

/** 子の文字 (文字列・数の並び) をつなげる。title に全文を載せるため。 */
function textOf(node: React.ReactNode): string {
  if (typeof node === "string" || typeof node === "number") return String(node)
  if (Array.isArray(node)) return node.map(textOf).join("")
  return ""
}

/**
 * 利用者が入れる文字 (コード・名前・単位・品目・理由。長さの上限が無い) を 1 行で出し、収まらなければ末尾を「…」で省略する。
 * 折り返さないので行の高さは変わらない。全文は title (マウスを乗せると出る) で読め、読み上げは文字そのものを読む
 * (省略は見た目だけ)。1024px 未満は省略せず、表の容器の中で横にスクロールする。
 *
 * 省略は 1 行に切る line-clamp で行う (`truncate` の nowrap だと表の列の最小幅が全文の幅になり、表が縮まない)。
 * 任意の文字の間で切れるので、列は全文の幅を上限に、ほかの列と幅を分け合う
 */
function TruncatedText({
  className,
  children,
  ...props
}: React.ComponentProps<"span">) {
  return (
    <span
      data-truncate=""
      title={textOf(children)}
      className={cn(
        "block lg:line-clamp-1 lg:break-all lg:whitespace-normal",
        className
      )}
      {...props}
    >
      {children}
    </span>
  )
}

/**
 * - `numeric`: 数値の列。右寄せ・等幅数字
 * - `sortable`: 見出しがソートできる列。数値の列なら、見出しの矢印の幅を右に空ける
 * - `ranked`: 見出しに並べる列の番号が出る列。数値の列なら、番号の幅も右に空ける
 * - `truncate`: 長い文字の列。1024px 以上では最小 96px まで縮め、中身を `TruncatedText` で省略する。
 *   中身が文字なら自分で包む。明細のように行を分けて並べるセルは、呼び出し側が行ごとに `TruncatedText` で包む
 */
function TableCell({
  className,
  children,
  numeric = false,
  sortable = false,
  ranked = false,
  truncate = false,
  ...props
}: React.ComponentProps<"td"> & { numeric?: boolean; sortable?: boolean; ranked?: boolean; truncate?: Truncate }) {
  const text = truncate && textOf(children) !== ""
  return (
    <td
      data-slot="table-cell"
      className={cn(
        "border-divider-subtle h-13 border-b px-3 align-middle whitespace-nowrap first:pl-0 last:pr-0 [&:has([role=checkbox])]:pr-0",
        numeric && "text-right tabular-nums",
        numeric && sortable && (ranked ? SORT_RANK_SLOT : SORT_ICON_SLOT),
        truncate && "lg:min-w-24",
        truncate === "wide" && "xl:min-w-56",
        className
      )}
      {...props}
    >
      {text ? <TruncatedText>{children}</TruncatedText> : children}
    </td>
  )
}

/** 操作の列のボタンの並び。左寄せで、縦は行の中央、1 行に並べる (`components/row-actions.tsx` が使う)。 */
function TableActions({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="table-actions"
      className={cn("flex items-center gap-2", className)}
      {...props}
    />
  )
}

function TableCaption({
  className,
  ...props
}: React.ComponentProps<"caption">) {
  return (
    <caption
      data-slot="table-caption"
      className={cn("mt-4 text-sm text-muted-foreground", className)}
      {...props}
    />
  )
}

export {
  Table,
  TableHeader,
  TableBody,
  TableFooter,
  TableHead,
  TableRow,
  TableCell,
  TableCaption,
  TableActions,
  TruncatedText,
}
