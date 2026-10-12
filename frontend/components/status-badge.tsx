import { TriangleAlert } from "lucide-react";
import type { StatusStyle, Tone } from "@/lib/statuses";

// 状況のバッジの見え方はここにだけ置く。淡い面と同系の濃い文字と、文字と同じ色の直径 6px の点で描き、
// 色だけに頼らず文字で区別する
const TONE_STYLE: Record<Tone, string> = {
  received: "bg-status-received text-status-received-foreground",
  partial: "bg-status-partial text-status-partial-foreground",
  allocated: "bg-status-allocated text-status-allocated-foreground",
  instructed: "bg-status-instructed text-status-instructed-foreground",
  shipped: "bg-status-shipped text-status-shipped-foreground",
  cancelled: "bg-status-cancelled text-status-cancelled-foreground",
};

/** かんばんの列の見出しの下線の色。バッジと同じ色相の 500 番。 */
export const TONE_LINE: Record<Tone, string> = {
  received: "border-status-received-line",
  partial: "border-status-partial-line",
  allocated: "border-status-allocated-line",
  instructed: "border-status-instructed-line",
  shipped: "border-status-shipped-line",
  cancelled: "border-status-cancelled-line",
};

const BASE =
  "rounded-badge inline-flex items-center gap-1.5 px-2 py-0.5 text-[13px] leading-5 font-medium whitespace-nowrap";

/**
 * 状況のバッジ。`style` は lib/statuses.ts の表から引く。API が表に無い値を返しても落とさず、値をそのまま出す。
 * `mark` は状況に重ねる印 (取消審査中・取消依頼中)。取消の審査と依頼は状況ではないので、別の札で添える。
 */
export function StatusBadge({ style, value, mark }: { style: StatusStyle | undefined; value?: string; mark?: string }) {
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      <span data-testid="status-badge" className={`${BASE} ${style ? TONE_STYLE[style.tone] : "bg-muted text-foreground"}`}>
        <svg aria-hidden viewBox="0 0 6 6" className="size-1.5 shrink-0 fill-current">
          <circle cx="3" cy="3" r="3" />
        </svg>
        {style?.label ?? value}
      </span>
      {mark && (
        <span data-testid="status-mark" className={`${BASE} bg-warning text-warning-foreground`}>
          {mark}
        </span>
      )}
    </span>
  );
}

/** 有効在庫が安全在庫を下回る在庫の札。 */
export function AlertBadge() {
  return (
    <span data-testid="alert-badge" className={`${BASE} bg-warning text-warning-foreground`}>
      <TriangleAlert aria-hidden className="size-3.5" />
      在庫不足
    </span>
  );
}
