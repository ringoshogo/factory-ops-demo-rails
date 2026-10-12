import { SortableHead } from "@/components/sortable-head";
import { TableHead } from "@/components/ui/table";
import type { Sort } from "@/lib/list";

/**
 * 表の列の定義。見出しとセルを同じ定義から描き、key を 2 回書かない。`sort` は API の orderBy の field の値で、
 * 持つ列だけが並べ替えの見出しになる。API で並べられない列は並べ替えの対象にしない (画面で並べると、
 * 1 ページの中だけが並び、ページをまたいだ並びと食い違う)。`numeric` は見出しとセルの両方に、`truncate` はセルに渡す。
 */
export type Column<F extends string = string> = {
  key: string;
  label: string;
  sort?: F;
  numeric?: boolean;
  truncate?: boolean;
};

/**
 * 並べ替えの見出しにする列を、API の orderBy の field の一覧から作る。`labels` は field ごとの見出しの文字で、
 * `Record<field, …>` なので、API が field を足すと型検査が落ち、見出しを足すまで通らない。
 */
export function sortColumns<F extends string>(labels: Record<F, string>, extra: Partial<Record<F, Omit<Column<F>, "key" | "label" | "sort">>> = {}) {
  return Object.fromEntries(
    (Object.keys(labels) as F[]).map((field) => [field, { key: field, label: labels[field], sort: field, ...extra[field] }]),
  ) as unknown as Record<F, Column<F>>;
}

/** 列の定義から見出しを描く。`sort` を持つ列は並べ替えの見出し、持たない列はただの見出しにする。 */
export function ColumnHeads<F extends string>({ columns, state }: { columns: readonly Column<F>[]; state: Sort<F> }) {
  return columns.map((c) =>
    c.sort ? (
      <SortableHead key={c.key} label={c.label} field={c.sort} state={state} numeric={c.numeric} />
    ) : (
      <TableHead key={c.key} numeric={c.numeric}>
        {c.label}
      </TableHead>
    ),
  );
}
