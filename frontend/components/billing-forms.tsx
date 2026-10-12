"use client";

import { useActionState, useId } from "react";
import { FieldError, FormError } from "@/components/form-errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { closeBillingPeriod, setBillingTerm } from "@/lib/actions/billing";
import { IDLE } from "@/lib/form-state";

type Customer = { id: string; name: string };

/** 取引先の締め日の設定。1〜28 か、月末の 31。admin にだけ出す。 */
export function BillingTermForm({ customer, closingDay }: { customer: Customer; closingDay: number | null }) {
  const [state, action, pending] = useActionState(setBillingTerm, IDLE);
  const id = useId();
  return (
    <form action={action} className="flex flex-wrap items-start gap-2" data-testid="billing-term-form">
      <input type="hidden" name="customerTenantId" value={customer.id} />
      <div className="space-y-1">
        <Label htmlFor={id} className="sr-only">
          {customer.name} の締め日
        </Label>
        <Input
          id={id}
          name="closingDay"
          type="number"
          min={1}
          max={31}
          defaultValue={closingDay ?? ""}
          className="w-24"
          aria-invalid={Boolean(state.fieldErrors?.closingDay)}
        />
        <FieldError state={state} name="closingDay" />
      </div>
      <Button type="submit" variant="outline" disabled={pending}>
        設定
      </Button>
      {state.status === "ok" && <span className="text-muted-foreground self-center text-[13px]">設定しました</span>}
      <FormError state={state} />
    </form>
  );
}

/**
 * 締め。取引先と締め日を選び、その日までに検収した未請求の明細を下書きの請求書にまとめる。締め日の既定は業務の今日の
 * 月末で、締め日の設定 (月末) と同じ日になる。成功すると請求書の詳細へ移る。admin にだけ出す。
 */
export function ClosePeriodForm({ customers, defaultDate }: { customers: readonly Customer[]; defaultDate: string }) {
  const [state, action, pending] = useActionState(closeBillingPeriod, IDLE);
  const id = useId();
  return (
    <form action={action} className="space-y-3" data-testid="close-period-form">
      <FormError state={state} />
      <div className="flex flex-wrap items-end gap-3">
        {/* select は最も長い選択肢の幅に広がるので、狭い画面では幅をフォームに合わせ、長い取引先の名前で横にはみ出さない */}
        <div className="w-full max-w-md min-w-0 space-y-1.5">
          <Label htmlFor={`${id}-customer`}>取引先</Label>
          <NativeSelect fullWidth className="w-full min-w-0" id={`${id}-customer`} name="customerTenantId" required defaultValue="">
            <option value="" disabled>
              選ぶ
            </option>
            {customers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </NativeSelect>
          <FieldError state={state} name="customerTenantId" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor={`${id}-date`}>締め日</Label>
          <Input id={`${id}-date`} name="closingDate" type="date" required defaultValue={defaultDate} className="w-44" />
          <FieldError state={state} name="closingDate" />
        </div>
        <Button type="submit" disabled={pending}>
          締める
        </Button>
      </div>
    </form>
  );
}
