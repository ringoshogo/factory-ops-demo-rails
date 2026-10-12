"use client";

import { FieldError } from "@/components/form-errors";
import { FieldRow, FormDialog } from "@/components/form-dialog";
import { Input } from "@/components/ui/input";
import { correctItemPrice, scheduleItemPrice } from "@/lib/actions/supplier-master";
import { yen } from "@/lib/format";

/**
 * 単価の改定の予約。改定日から新しい単価が効き、改定日より前に受けた受注の単価は変わらない。改定日は業務の今日より後にする。
 */
export function SchedulePriceDialog({ itemId, businessDate }: { itemId: string; businessDate: string | null }) {
  return (
    <FormDialog label="単価の改定を予約" title="単価の改定の予約" action={scheduleItemPrice} submitLabel="予約">
      {(state) => (
        <>
          <input type="hidden" name="itemId" value={itemId} />
          <FieldRow id="schedule-effective-on" label="改定日" error={<FieldError state={state} name="effectiveOn" />}>
            <Input id="schedule-effective-on" name="effectiveOn" type="date" required min={businessDate ?? undefined} />
          </FieldRow>
          <FieldRow id="schedule-unit-price" label="新しい単価（円・税抜き）" error={<FieldError state={state} name="unitPrice" />}>
            <Input id="schedule-unit-price" name="unitPrice" inputMode="numeric" required />
          </FieldRow>
        </>
      )}
    </FormDialog>
  );
}

/**
 * 単価の訂正。入力の誤りを直すもので、行を書き換えずに記録期間を閉じて新しい行を足す。訂正の前に信じていた単価は、
 * 記録の時点を指定して読むと見える。
 */
export function CorrectPriceDialog({ itemId, itemPriceId, current }: { itemId: string; itemPriceId: string; current: string }) {
  return (
    <FormDialog
      label="訂正"
      variant="outline"
      size="sm"
      title="単価の訂正"
      description={`いまの記録は ${yen(current)} 円です。入力の誤りを直すときだけ使います。`}
      action={correctItemPrice}
      submitLabel="訂正"
    >
      {(state) => (
        <>
          <input type="hidden" name="itemId" value={itemId} />
          <input type="hidden" name="itemPriceId" value={itemPriceId} />
          <FieldRow id="correct-unit-price" label="正しい単価（円・税抜き）" error={<FieldError state={state} name="unitPrice" />}>
            <Input id="correct-unit-price" name="unitPrice" inputMode="numeric" required defaultValue={current} />
          </FieldRow>
          <FieldRow id="correct-reason" label="訂正の理由" error={<FieldError state={state} name="reason" />}>
            <Input id="correct-reason" name="reason" required />
          </FieldRow>
        </>
      )}
    </FormDialog>
  );
}
