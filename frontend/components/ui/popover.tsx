"use client"

import { Popover as PopoverPrimitive } from "@base-ui/react/popover"
import { cn } from "cn"

/**
 * 浮く部品 (メニュー・ポップオーバー) の置き方と面 (仕様 cycle-03 §4「浮く部品の構成」)。
 * メニュー (ui/menu) もここから取り、配置・幅・面を 2 か所に書かない。
 *
 * - 配置: ボタンの下・左端そろえ・6px 離す。画面端での反転・ずらしは Positioner の既定に任せ、端から 8px 空ける
 * - 幅: 最小はボタンの幅、最大は min(320px, 100vw − 16px)。390px 幅でも画面の外へ出ない
 * - 開閉で拡大縮小・透明度を動かさない (開いている途中に測った寸法・色が最終の形とずれる)
 */
export const FLOATING_POSITION = {
  side: "bottom",
  align: "start",
  sideOffset: 6,
  collisionPadding: 8,
} as const

export const FLOATING_SURFACE =
  "min-w-[var(--anchor-width)] max-w-[min(320px,calc(100vw-16px))] overflow-y-auto rounded-card bg-card text-card-foreground shadow-popup outline-none"

function Popover(props: PopoverPrimitive.Root.Props) {
  return <PopoverPrimitive.Root {...props} />
}

const PopoverTrigger = PopoverPrimitive.Trigger
const PopoverTitle = PopoverPrimitive.Title
const PopoverClose = PopoverPrimitive.Close

/**
 * Portal → Positioner → Popup (1.8.0 の Popup は Positioner の文脈が無いと例外になる)。
 * 閉じたら DOM から外す (keepMounted を付けない)。高さの上限は利用できる高さ。
 */
function PopoverContent({ className, ...props }: PopoverPrimitive.Popup.Props) {
  return (
    <PopoverPrimitive.Portal>
      <PopoverPrimitive.Positioner {...FLOATING_POSITION} className="z-50">
        <PopoverPrimitive.Popup
          className={cn(FLOATING_SURFACE, "max-h-[var(--available-height)] p-4", className)}
          {...props}
        />
      </PopoverPrimitive.Positioner>
    </PopoverPrimitive.Portal>
  )
}

export { Popover, PopoverClose, PopoverContent, PopoverTitle, PopoverTrigger }
