import { ChevronDown } from "lucide-react";
import { cn } from "cn";
import type { ComponentProps } from "react";
import { CONTROL_SURFACE } from "@/components/ui/input";

/**
 * ブラウザ標準の select。矢印だけを自前のアイコンに替える。
 *
 * 標準の矢印は位置を調整できず、右端に触れそうなほど近い。`appearance-none` で消し、
 * 右端から 12px 内側にアイコンを置く。`pr-9` で選んだ文字が矢印に重ならない。
 * `fullWidth` は親の幅いっぱいに広げる (フォームの1列に置くとき)。外側の枠が幅を決めるので、
 * select に `w-full` を付けるだけでは広がらない。無効のときは矢印も薄くする。
 */
export function NativeSelect({
  className = "",
  fullWidth = false,
  ...props
}: ComponentProps<"select"> & { fullWidth?: boolean }) {
  return (
    <div className={`relative ${fullWidth ? "flex w-full" : "inline-flex"}`}>
      <select
        {...props}
        // pr-9 は最後に置く (呼び出し側の px-* に消されると文字が矢印に重なる)
        className={cn("peer h-9 appearance-none px-3 text-sm", CONTROL_SURFACE, className, "pr-9")}
      />
      <ChevronDown
        aria-hidden
        className="text-muted-foreground pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 peer-disabled:opacity-50"
      />
    </div>
  );
}
