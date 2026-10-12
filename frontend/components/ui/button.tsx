import { Button as ButtonPrimitive } from "@base-ui/react/button"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "cn"

/**
 * 小さいボタンの高さ。かんばんのカードの最下段もこの高さで固定し、ボタンの有無で
 * カードの高さを変えない。
 */
const BUTTON_SM_HEIGHT = "h-7.5"

const buttonVariants = cva(
  // フォーカスの輪郭は globals.css の :focus-visible に任せる (全部品で同じ)。
  // 色は遷移させない: テーマを切り替えた直後に中間の色が残り、文字のコントラストが一時的に落ちる
  "group/button inline-flex shrink-0 items-center justify-center rounded-control text-sm font-medium whitespace-nowrap transition-transform select-none active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
  {
    variants: {
      variant: {
        // 主ボタン: アクセントの面と内側の影 (縁・下の陰・上の光)
        default: "bg-primary text-primary-foreground shadow-primary hover:bg-primary-hover",
        // 二次ボタン: パネルの面と、3:1 の縁取りを内側の影で描く
        outline:
          "bg-card text-foreground shadow-control hover:bg-muted aria-expanded:bg-muted",
        secondary:
          "bg-secondary text-secondary-foreground hover:bg-[color-mix(in_oklch,var(--secondary),var(--foreground)_5%)] aria-expanded:bg-secondary aria-expanded:text-secondary-foreground",
        ghost:
          "hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground dark:hover:bg-muted/50",
        destructive:
          "bg-destructive/10 text-destructive hover:bg-destructive/20 focus-visible:border-destructive/40 focus-visible:ring-destructive/20 dark:bg-destructive/20 dark:hover:bg-destructive/30 dark:focus-visible:ring-destructive/40",
        link: "text-link hover:text-link-hover",
        // 絞り込みボタン。値なしは二次ボタンと同じ縁取りで、文字は文字 2
        filter: "bg-card text-foreground-2 shadow-control hover:bg-muted aria-expanded:bg-muted",
        // 値を選んでいる絞り込みボタン: --filter-active-* の面・文字・内側 1px の縁取り
        filterActive: "bg-filter-active text-filter-active-foreground shadow-filter-active",
      },
      size: {
        default:
          "h-9 gap-2 px-3.5 has-data-[icon=inline-end]:pr-3 has-data-[icon=inline-start]:pl-3",
        xs: "h-6 gap-1 rounded-[min(var(--radius-md),10px)] px-2 text-xs in-data-[slot=button-group]:rounded-lg has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3",
        sm: `${BUTTON_SM_HEIGHT} gap-1.5 px-3 text-[13px] has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2 [&_svg:not([class*='size-'])]:size-3.5`,
        // 絞り込みボタン: 高さ 32px・左右 12px・13px・アイコン 14px・間 6px
        filter: "h-8 gap-1.5 px-3 text-[13px] [&_svg:not([class*='size-'])]:size-3.5",
        lg: "h-9 gap-1.5 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
        icon: "size-8",
        "icon-xs":
          "size-6 rounded-[min(var(--radius-md),10px)] in-data-[slot=button-group]:rounded-lg [&_svg:not([class*='size-'])]:size-3",
        "icon-sm":
          "size-7 rounded-[min(var(--radius-md),12px)] in-data-[slot=button-group]:rounded-lg",
        "icon-lg": "size-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

function Button({
  className,
  variant = "default",
  size = "default",
  ...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>) {
  return (
    <ButtonPrimitive
      data-slot="button"
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
}

export { Button, buttonVariants, BUTTON_SM_HEIGHT }
