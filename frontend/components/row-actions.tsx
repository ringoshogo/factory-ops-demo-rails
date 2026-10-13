"use client";

import { Ellipsis } from "lucide-react";
import { useId } from "react";
import { cn } from "cn";
import { Button, buttonVariants } from "@/components/ui/button";
import { Menu, MenuContent, MenuItem, MenuTrigger } from "@/components/ui/menu";
import { TableActions } from "@/components/ui/table";

export type RowAction = {
  label: string;
  variant?: "default" | "outline" | "ghost";
  /** 押したときの処理 (ダイアログを開く等) */
  onSelect?: () => void;
  /** フォームで送る操作 (サーバーの action と隠し項目) */
  form?: { action: (form: FormData) => void; fields: Record<string, string> };
};

/**
 * 表の行の操作。1280px 以上と 1024px 未満はボタンを並べ、
 * 1024〜1279px は「⋯」のボタン 1 つ (メニュー) にまとめて、表をパネルに収める。
 * 出し分けは CSS の display で行うので、隠れている方はアクセシビリティツリーにもタブ順にも出ない。
 *
 * フォームで送る操作は、フォームを 1 つだけ置き (中身は隠し項目だけ)、並べたボタンは `form` 属性で、
 * メニューの項目は `requestSubmit()` で同じフォームを送る (送り方を 2 つ持たない)。
 *
 * `name` は ⋯ のボタンの名前。どの行の操作か分かるもの (「ITM-001 の操作」「受注 10 の操作」)。
 */
export function RowActions({ name, actions }: { name: string; actions: RowAction[] }) {
  const id = useId();
  const formId = (i: number) => `${id}-form-${i}`;
  const run = (action: RowAction, i: number) => {
    if (action.form) (document.getElementById(formId(i)) as HTMLFormElement | null)?.requestSubmit();
    else action.onSelect?.();
  };

  return (
    <>
      {actions.map((a, i) =>
        a.form ? (
          <form key={i} id={formId(i)} action={a.form.action} hidden>
            {Object.entries(a.form.fields).map(([key, value]) => (
              <input key={key} type="hidden" name={key} value={value} />
            ))}
          </form>
        ) : null,
      )}
      <TableActions className="lg:hidden xl:flex">
        {actions.map((a, i) => (
          <Button
            key={i}
            size="sm"
            variant={a.variant ?? "default"}
            type={a.form ? "submit" : "button"}
            form={a.form ? formId(i) : undefined}
            onClick={a.form ? undefined : a.onSelect}
          >
            {a.label}
          </Button>
        ))}
      </TableActions>
      <TableActions className="hidden lg:flex xl:hidden">
        <Menu>
          <MenuTrigger aria-label={name} className={cn(buttonVariants({ variant: "outline", size: "sm" }), "px-2")}>
            <Ellipsis aria-hidden />
          </MenuTrigger>
          <MenuContent>
            {actions.map((a, i) => (
              <MenuItem key={i} onClick={() => run(a, i)}>
                {a.label}
              </MenuItem>
            ))}
          </MenuContent>
        </Menu>
      </TableActions>
    </>
  );
}
