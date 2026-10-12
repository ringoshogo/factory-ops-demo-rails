import * as React from "react"
import { Input as InputPrimitive } from "@base-ui/react/input"
import { cn } from "cn"

/**
 * 入力欄・select・日付ボタンの面と縁取り (仕様 cycle-03 §3 共通部品)。
 * ライトは透明 (パネルの白が見える)。ダークの面を `dark:` 変種で書くのは、
 * 既存 E2E「部品の `dark:` 指定も効く」が測る対象を残すため。
 * 縁取りは内側の影で描き (高さを変えない)、パネル・台の上で 3:1 以上になる。
 */
export const CONTROL_SURFACE = "rounded-control bg-transparent shadow-control dark:bg-white/4"

function Input({ className, type, ...props }: React.ComponentProps<"input">) {
  return (
    <InputPrimitive
      type={type}
      data-slot="input"
      className={cn(
        "h-9 w-full min-w-0 px-3 py-1 text-base file:inline-flex file:h-6 file:border-0 file:bg-transparent file:text-sm file:font-medium file:text-foreground placeholder:text-muted-foreground disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:ring-2 aria-invalid:ring-destructive md:text-sm",
        CONTROL_SURFACE,
        className
      )}
      {...props}
    />
  )
}

export { Input }
