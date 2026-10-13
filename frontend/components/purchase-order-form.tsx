"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useActionState, useState } from "react";
import { DateField } from "@/components/date-field";
import { ErrorNotice } from "@/components/error-notice";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { placePurchaseOrder } from "@/lib/actions/purchasing";
import { IDLE, type FormState } from "@/lib/form-state";
import { patchHref } from "@/lib/query";

export type OrderableSupplier = { id: string; name: string };

/** 入力欄の下の誤り。鍵は UserError の path を `.` でつないだもの。 */
function FieldError({ state, name }: { state: FormState; name: string }) {
  const message = state.fieldErrors?.[name];
  return message ? (
    <p data-testid="field-error" className="text-destructive text-[13px]">
      {message}
    </p>
  ) : null;
}

/**
 * 発注の登録のフォーム。取引先を選ぶと URL の `supplier` を差し替え、サーバーがその相手のカタログを読み直して
 * フォームの横に並べる。入力した明細は、同じ画面の描き直しなので残る。
 *
 * 取引先の選択肢は発注の付与がある相手だけだが、URL の `supplier` が選択肢に無い ID でも、その値のまま送る。
 * 発注できるかは Rails が取引関係と付与で決めるので、画面で先回りして止めない (失効の後の発注は NOT_PERMITTED になる)。
 * 明細は自社品番で書き、受注側は自分の対応表で品目に照らす。
 */
export function PurchaseOrderForm({
  suppliers,
  selected,
  businessDate,
}: {
  suppliers: readonly OrderableSupplier[];
  selected: string;
  businessDate: string;
}) {
  const [state, submit, pending] = useActionState<FormState, FormData>(placePurchaseOrder, IDLE);
  const [lineCount, setLineCount] = useState(1);
  const router = useRouter();
  const pathname = usePathname();
  const params = useSearchParams();
  const unknown = selected !== "" && !suppliers.some((s) => s.id === selected);

  return (
    <form action={submit} className="space-y-6">
      {state.status === "error" && state.message && <ErrorNotice data-testid="form-error">{state.message}</ErrorNotice>}

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="supplierTenantId">取引先</Label>
          <NativeSelect
            fullWidth
            id="supplierTenantId"
            name="supplierTenantId"
            className="w-full"
            value={selected}
            onChange={(e) =>
              router.replace(patchHref(pathname, params, { supplier: e.target.value || null, after: null }), {
                scroll: false,
              })
            }
          >
            <option value="">選択してください</option>
            {suppliers.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
            {unknown && <option value={selected}>発注の付与が見つからない取引先</option>}
          </NativeSelect>
          <FieldError state={state} name="supplierTenantId" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="desiredDeliveryOn">希望納期</Label>
          <DateField id="desiredDeliveryOn" name="desiredDeliveryOn" referenceDate={businessDate} clearable />
          <FieldError state={state} name="desiredDeliveryOn" />
        </div>
      </div>

      <div className="space-y-3">
        {Array.from({ length: lineCount }, (_, i) => (
          <div key={i} data-testid="order-line-input" className="rounded-card grid gap-3 border p-3 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor={`partNumber-${i}`}>自社品番</Label>
              <Input id={`partNumber-${i}`} name="partNumber" autoComplete="off" />
              <FieldError state={state} name={`lines.${i}.partNumber`} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`quantity-${i}`}>数量</Label>
              <Input id={`quantity-${i}`} name="quantity" type="number" min={1} defaultValue="1" />
              <FieldError state={state} name={`lines.${i}.quantity`} />
            </div>
          </div>
        ))}
        <FieldError state={state} name="lines" />
        <Button type="button" variant="outline" size="sm" onClick={() => setLineCount((n) => n + 1)}>
          明細を追加
        </Button>
      </div>

      <Button type="submit" disabled={pending}>
        発注を登録
      </Button>
    </form>
  );
}
