"use client";

import { useState } from "react";
import { FieldError } from "@/components/form-errors";
import { FieldRow, FormDialog } from "@/components/form-dialog";
import { Input } from "@/components/ui/input";
import { NativeSelect } from "@/components/ui/native-select";
import { adjustStock } from "@/lib/actions/supplier-master";

export type AdjustTarget = { itemId: string; code: string; name: string; onHand: number; allocated: number; available: number };

/**
 * 入出庫の調整のダイアログ。数量は現在庫に足す (入庫)・引く (出庫) 数で、種類に合わせて欄の名前を変え、調整の後の
 * 現在庫を目安として出す。記録できるかどうか (出庫で現在庫が引当を下回らないか) は、表示している在庫が古いことが
 * あるので画面で判定せず、API の応答をそのまま見せる。
 */
export function StockAdjustDialog({ target }: { target: AdjustTarget }) {
  return (
    <FormDialog
      label="入出庫調整"
      variant="outline"
      size="sm"
      title={`入出庫調整（${target.code} ${target.name}）`}
      action={adjustStock}
      submitLabel="記録"
    >
      {(state) => <AdjustFields target={target} error={(name) => <FieldError state={state} name={name} />} />}
    </FormDialog>
  );
}

function AdjustFields({ target, error }: { target: AdjustTarget; error: (name: string) => React.ReactNode }) {
  const [type, setType] = useState<"INBOUND" | "OUTBOUND">("INBOUND");
  const [quantity, setQuantity] = useState("1");
  const parsed = /^\d+$/.test(quantity.trim()) ? Number(quantity) : null;
  const after = parsed && parsed > 0 ? target.onHand + (type === "INBOUND" ? parsed : -parsed) : null;
  // 目安の表示だけ。記録できるかどうかは API が決める
  const blocked = type === "OUTBOUND" && after !== null && after < target.allocated;

  return (
    <>
      <input type="hidden" name="itemId" value={target.itemId} />
      <p data-testid="adjust-summary" className="text-muted-foreground text-sm">
        現在庫 {target.onHand} / 引当 {target.allocated} / 有効在庫 {target.available}
      </p>
      <FieldRow id="adjust-type" label="種類" error={error("type")}>
        <NativeSelect
          fullWidth
          id="adjust-type"
          name="type"
          value={type}
          onChange={(e) => setType(e.target.value === "OUTBOUND" ? "OUTBOUND" : "INBOUND")}
          className="w-full"
        >
          <option value="INBOUND">入庫</option>
          <option value="OUTBOUND">出庫</option>
        </NativeSelect>
      </FieldRow>
      <FieldRow
        id="adjust-quantity"
        label={type === "INBOUND" ? "数量（現在庫に足す）" : "数量（現在庫から引く）"}
        error={error("quantity")}
      >
        <Input
          id="adjust-quantity"
          name="quantity"
          type="number"
          min={1}
          value={quantity}
          onChange={(e) => setQuantity(e.target.value)}
        />
        <p
          data-testid="adjust-preview"
          aria-live="polite"
          className={`text-sm tabular-nums ${blocked ? "text-destructive font-medium" : "text-muted-foreground"}`}
        >
          {after === null ? "数量を入れると、調整の後の現在庫を出します" : `調整の後の現在庫 ${target.onHand} → ${after}`}
          {blocked && `（引当 (${target.allocated}) を下回るので記録できません）`}
        </p>
      </FieldRow>
      <FieldRow id="adjust-reason" label="理由" error={error("reason")}>
        <Input id="adjust-reason" name="reason" placeholder="棚卸の調整・破損など" />
      </FieldRow>
    </>
  );
}
