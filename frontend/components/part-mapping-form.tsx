"use client";

import { useActionState, useState } from "react";
import { FieldError, FormError } from "@/components/form-errors";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { registerPartMapping } from "@/lib/actions/supplier-master";
import { IDLE } from "@/lib/form-state";

type Option = { id: string; label: string };

/** 照合待ちの明細の 1 行。押すと、その取引先と得意先品番が登録の入力欄に入る。 */
export type AwaitingLine = { key: string; customerTenantId: string; customerName: string; orderNo: string; customerPartNumber: string; quantity: number };

/**
 * 品番の対応表の登録。取引先・得意先品番・自社の品目を選んで送る。照合待ちの受注の明細を押すと、取引先と得意先品番が
 * 入る。対応がそろうと、照合待ちの受注はイベントで受注確定へ進む。
 */
export function PartMappingForm({
  customers,
  items,
  awaiting,
}: {
  customers: readonly Option[];
  items: readonly Option[];
  awaiting: readonly AwaitingLine[];
}) {
  const [state, submit, pending] = useActionState(registerPartMapping, IDLE);
  const [customer, setCustomer] = useState(customers[0]?.id ?? "");
  const [partNumber, setPartNumber] = useState("");

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <form action={submit} className="space-y-3" aria-label="品番の対応の登録">
        <h2 className="text-base font-semibold">対応を登録</h2>
        <div className="space-y-1.5">
          <Label htmlFor="mapping-customer">取引先</Label>
          <NativeSelect
            fullWidth
            id="mapping-customer"
            name="customerTenantId"
            value={customer}
            onChange={(e) => setCustomer(e.target.value)}
            className="w-full"
          >
            {customers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </NativeSelect>
          <FieldError state={state} name="customerTenantId" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="mapping-part-number">得意先品番</Label>
          <Input
            id="mapping-part-number"
            name="customerPartNumber"
            required
            value={partNumber}
            onChange={(e) => setPartNumber(e.target.value)}
          />
          <FieldError state={state} name="customerPartNumber" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="mapping-item">自社の品目</Label>
          <NativeSelect fullWidth id="mapping-item" name="itemId" className="w-full" required defaultValue="">
            <option value="" disabled>
              品目を選ぶ
            </option>
            {items.map((i) => (
              <option key={i.id} value={i.id}>
                {i.label}
              </option>
            ))}
          </NativeSelect>
          <FieldError state={state} name="itemId" />
        </div>
        <FormError state={state} />
        {state.status === "ok" && (
          <p role="status" className="text-muted-foreground text-[13px]">
            登録しました。照合待ちの受注は、対応がそろうと受注確定へ進みます。
          </p>
        )}
        <Button type="submit" disabled={pending}>
          登録
        </Button>
      </form>

      <div className="space-y-3">
        <h2 className="text-base font-semibold">照合待ちの明細</h2>
        {awaiting.length === 0 ? (
          <p data-testid="no-awaiting" className="text-muted-foreground text-sm">
            照合待ちの受注はありません。
          </p>
        ) : (
          <ul className="space-y-1">
            {awaiting.map((line) => (
              <li key={line.key}>
                <button
                  type="button"
                  data-testid="awaiting-line"
                  onClick={() => {
                    setCustomer(line.customerTenantId);
                    setPartNumber(line.customerPartNumber);
                  }}
                  className="rounded-control hover:bg-muted flex w-full flex-wrap items-baseline justify-between gap-x-3 px-2 py-1.5 text-left text-sm"
                >
                  <span className="font-medium">{line.customerPartNumber}</span>
                  <span className="text-muted-foreground min-w-0 text-xs">
                    {line.orderNo}・{line.customerName}・{line.quantity}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
