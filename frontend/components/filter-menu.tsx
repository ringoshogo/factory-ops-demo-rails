"use client";

import {
  ArrowLeftRight,
  Ban,
  Building2,
  CircleDot,
  Layers,
  Truck,
  type LucideIcon,
} from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { FilterButtonLabel, filterButtonClass } from "@/components/filter-bar";
import { Menu, MenuContent, MenuRadioGroup, MenuRadioItem, MenuTrigger } from "@/components/ui/menu";
import { RESET_PAGE } from "@/lib/list";
import { patchHref } from "@/lib/query";

/** アイコンは名前で受ける (サーバー部品の一覧から関数を渡せないため)。 */
const ICONS = {
  status: CircleDot,
  customer: Building2,
  cancel: Ban,
  stock: Layers,
  movement: ArrowLeftRight,
  shipping: Truck,
} satisfies Record<string, LucideIcon>;

export type FilterOption = { value: string; label: string };

/**
 * 1 つ選ぶ絞り込みのボタン。押すとメニューを開き、選ぶとその時点の URL に `param` の差し替えを当てた URL へ移り、
 * 1 ページ目に戻る。
 *
 * - `options` の先頭は解除の選択肢 (値 "")。選ぶと `param` を URL から外す
 * - `value` が選択肢に無いときは、その値をそのまま出す
 * - `clear`: 一緒に外すキー
 */
export function FilterMenu({
  label,
  icon,
  param,
  value,
  options,
  clear = [],
}: {
  label: string;
  icon: keyof typeof ICONS;
  param: string;
  value: string;
  options: FilterOption[];
  clear?: string[];
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const router = useRouter();
  const active = value !== "";
  const shown = options.find((o) => o.value === value)?.label ?? value;

  function select(next: string) {
    const patch: Record<string, string | null> = { [param]: next === "" ? null : next, ...RESET_PAGE };
    for (const key of clear) patch[key] = null;
    router.push(patchHref(pathname, params, patch), { scroll: false });
  }

  return (
    <Menu>
      <MenuTrigger className={filterButtonClass(active)}>
        <FilterButtonLabel icon={ICONS[icon]} label={label} value={shown} active={active} />
      </MenuTrigger>
      <MenuContent>
        <MenuRadioGroup value={value} onValueChange={(next: string) => select(next)}>
          {options.map((o) => (
            <MenuRadioItem key={o.value} value={o.value}>
              {o.label}
            </MenuRadioItem>
          ))}
        </MenuRadioGroup>
      </MenuContent>
    </Menu>
  );
}
