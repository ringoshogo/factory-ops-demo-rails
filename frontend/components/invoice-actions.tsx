"use client";

import { useActionState } from "react";
import { FormError } from "@/components/form-errors";
import { Button } from "@/components/ui/button";
import { discardDraftInvoice, issueInvoice } from "@/lib/actions/billing";
import { IDLE } from "@/lib/form-state";

/**
 * 下書きの請求書の確定と破棄。確定すると請求書番号が振られ、発注側に受領請求書が届き、取り消せない。
 * 破棄すると明細は未請求に戻る。どちらも admin にだけ出す。
 */
export function InvoiceActions({ invoiceId }: { invoiceId: string }) {
  const [issueState, issue, issuing] = useActionState(issueInvoice, IDLE);
  const [discardState, discard, discarding] = useActionState(discardDraftInvoice, IDLE);
  const pending = issuing || discarding;
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        <form action={issue}>
          <input type="hidden" name="invoiceId" value={invoiceId} />
          <Button type="submit" disabled={pending}>
            確定する
          </Button>
        </form>
        <form action={discard}>
          <input type="hidden" name="invoiceId" value={invoiceId} />
          <Button type="submit" variant="outline" disabled={pending}>
            下書きを破棄
          </Button>
        </form>
      </div>
      <FormError state={issueState} />
      <FormError state={discardState} />
    </div>
  );
}
