"use client"

import { Menu as MenuPrimitive } from "@base-ui/react/menu"
import { CheckIcon } from "lucide-react"
import { cn } from "cn"
import { FLOATING_POSITION, FLOATING_SURFACE } from "@/components/ui/popover"

/** 1 つ選ぶメニュー。フォーカスを閉じ込めない (`modal={false}`)。 */
function Menu(props: MenuPrimitive.Root.Props) {
  return <MenuPrimitive.Root modal={false} {...props} />
}

const MenuTrigger = MenuPrimitive.Trigger
const MenuRadioGroup = MenuPrimitive.RadioGroup

/**
 * Portal → Positioner → Popup (1.8.0 の Popup は Positioner の文脈が無いと例外になる)。
 * 高さは min(320px, 利用できる高さ) までで、中を縦にスクロールする。
 */
function MenuContent({ className, ...props }: MenuPrimitive.Popup.Props) {
  return (
    <MenuPrimitive.Portal>
      <MenuPrimitive.Positioner {...FLOATING_POSITION} className="z-50">
        <MenuPrimitive.Popup
          className={cn(FLOATING_SURFACE, "max-h-[min(320px,var(--available-height))] p-1", className)}
          {...props}
        />
      </MenuPrimitive.Positioner>
    </MenuPrimitive.Portal>
  )
}

/**
 * 1 つ選ぶ項目。選ぶと閉じる (`closeOnClick` の既定は false なので明示する)。
 * 選んでいる項目は Base UI が付ける `aria-checked="true"` と、左の印 (--link の Check)・文字の 500 で示す。
 * 印の幅は選んでいない項目でも空けておき、文字の位置をそろえる。
 */
function MenuRadioItem({ className, children, ...props }: MenuPrimitive.RadioItem.Props) {
  return (
    <MenuPrimitive.RadioItem
      closeOnClick
      className={cn(
        "flex min-h-8 cursor-default items-center gap-2 rounded-control py-1.5 pr-3 pl-2 text-sm select-none focus-visible:-outline-offset-2 data-checked:font-medium data-highlighted:bg-muted",
        className
      )}
      {...props}
    >
      <span className="flex size-4 shrink-0 items-center justify-center">
        <MenuPrimitive.RadioItemIndicator className="text-link">
          <CheckIcon aria-hidden className="size-4" />
        </MenuPrimitive.RadioItemIndicator>
      </span>
      <span className="min-w-0 truncate">{children}</span>
    </MenuPrimitive.RadioItem>
  )
}

/** 操作の項目 (表の行の ⋯ のメニュー)。選ぶと閉じる (Base UI の既定)。 */
function MenuItem({ className, ...props }: MenuPrimitive.Item.Props) {
  return (
    <MenuPrimitive.Item
      className={cn(
        "flex min-h-8 cursor-default items-center rounded-control px-3 py-1.5 text-sm select-none focus-visible:-outline-offset-2 data-highlighted:bg-muted",
        className
      )}
      {...props}
    />
  )
}

export { Menu, MenuContent, MenuItem, MenuRadioGroup, MenuRadioItem, MenuTrigger }
