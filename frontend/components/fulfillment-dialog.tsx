"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { DateField } from "@/components/date-field";
import { ErrorNotice } from "@/components/error-notice";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DIALOG_FORM,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  allocateSalesOrder,
  cancelShippingInstruction,
  createShippingInstruction,
  postShipment,
} from "@/lib/actions/fulfillment";
import { IDLE, type FormState } from "@/lib/form-state";

/** ダイアログで行う受注と出荷依頼の操作。 */
export type FulfillmentKind = "allocate" | "instruct" | "ship" | "cancelInstruction";

/** 操作の対象。開いた時点の値を写して持つ。 */
export type FulfillmentTarget = {
  salesOrderId: string;
  shipmentRequestId: string | null;
  orderNo: string;
  customerName: string;
  /** 出荷予定日の既定値 (希望納期か出荷期限)。無ければ業務の今日。 */
  dueDate: string | null;
};

type Opened = { kind: FulfillmentKind; target: FulfillmentTarget; session: number };

/**
 * 受注と出荷依頼の操作のダイアログ。画面が 1 つだけ持ち、`open` で開く。操作の後の読み直しで、操作したカードや行は
 * 別の列へ移るか作り直されるので、ダイアログをカードや行の中に置くと結果の表示が消える。
 * `finalFocus` は閉じた後にフォーカスを戻す先を返す (戻す先が無ければ既定の動き)。
 */
export function useFulfillmentDialog({
  businessDate,
  finalFocus,
}: {
  businessDate: string;
  finalFocus?: (target: FulfillmentTarget) => HTMLElement | null;
}) {
  const [opened, setOpened] = useState<Opened | null>(null);
  // 開閉と中身を分ける。閉じるアニメーションの間は中身を残し、終わってから消す (先に消すと空のダイアログが一瞬見える)
  const [isOpen, setIsOpen] = useState(false);
  const session = useRef(0);
  const last = useRef<FulfillmentTarget | null>(null);

  const open = (kind: FulfillmentKind, target: FulfillmentTarget) => {
    session.current += 1;
    last.current = target;
    setOpened({ kind, target, session: session.current });
    setIsOpen(true);
  };

  const dialog = (
    <Dialog open={isOpen} onOpenChange={setIsOpen} onOpenChangeComplete={(next) => !next && setOpened(null)}>
      <DialogContent
        showCloseButton={false}
        finalFocus={() => (last.current && finalFocus?.(last.current)) || true}
      >
        {opened && <FulfillmentForm key={opened.session} kind={opened.kind} target={opened.target} businessDate={businessDate} />}
      </DialogContent>
    </Dialog>
  );
  return { open, dialog };
}

const TITLES: Record<FulfillmentKind, string> = {
  allocate: "引当",
  instruct: "出荷指示",
  ship: "出荷実績計上",
  cancelInstruction: "出荷指示の取消",
};

const DONE: Record<FulfillmentKind, string> = {
  allocate: "引当を実行しました。",
  instruct: "出荷指示を作成しました。",
  ship: "出荷実績を計上しました。",
  cancelInstruction: "出荷指示を取り消しました。",
};

const SUBMIT: Record<FulfillmentKind, string> = {
  allocate: "引当する",
  instruct: "出荷指示を作成",
  ship: "計上する",
  cancelInstruction: "取り消す",
};

const ACTIONS: Record<FulfillmentKind, (prev: FormState, form: FormData) => Promise<FormState>> = {
  allocate: allocateSalesOrder,
  instruct: createShippingInstruction,
  ship: postShipment,
  cancelInstruction: cancelShippingInstruction,
};

function FulfillmentForm({
  kind,
  target,
  businessDate,
}: {
  kind: FulfillmentKind;
  target: FulfillmentTarget;
  businessDate: string;
}) {
  const [state, submit, pending] = useActionState(ACTIONS[kind], IDLE);
  const done = state.status === "ok";
  return (
    <form action={submit} className={DIALOG_FORM}>
      <DialogHeader>
        <DialogTitle>{TITLES[kind]}</DialogTitle>
        <DialogDescription>
          {target.orderNo}・{target.customerName}
        </DialogDescription>
      </DialogHeader>
      <DialogBody>
        <input type="hidden" name="sales_order_id" value={target.salesOrderId} />
        <input type="hidden" name="shipment_request_id" value={target.shipmentRequestId ?? ""} />
        {kind === "allocate" && (
          <p className="text-sm">全明細を、有効在庫の範囲で引き当てます。在庫が足りなければ、ある分だけ引き当てて一部引当になります。</p>
        )}
        {kind === "instruct" && (
          <div className="space-y-1">
            <Label htmlFor="fulfillment-planned-date">出荷予定日</Label>
            <DateField
              id="fulfillment-planned-date"
              name="planned_date"
              defaultValue={target.dueDate ?? businessDate}
              referenceDate={businessDate}
              disabled={done}
            />
          </div>
        )}
        {kind === "ship" && (
          <>
            <div className="space-y-1">
              <Label htmlFor="fulfillment-shipped-on">出荷日</Label>
              <DateField
                id="fulfillment-shipped-on"
                name="shipped_on"
                defaultValue={businessDate}
                referenceDate={businessDate}
                disabled={done}
              />
            </div>
            <p className="text-sm">全明細の出荷実績を計上します。計上すると在庫が減り、取り消せません。</p>
          </>
        )}
        {kind === "cancelInstruction" && (
          <p className="text-sm">出荷指示を取り消し、出荷依頼を出荷待ちに戻します。</p>
        )}
        <ResultRegion active={state.status !== "idle"}>
          {state.status === "ok" && (
            <p className="bg-info text-info-foreground rounded-control px-3 py-2 text-sm">{DONE[kind]}</p>
          )}
          {state.status === "error" && (
            <ErrorNotice data-testid="form-error">
              {[state.message, ...Object.values(state.fieldErrors ?? {})].filter(Boolean).join(" ")}
            </ErrorNotice>
          )}
        </ResultRegion>
      </DialogBody>
      <DialogFooter>
        <DialogClose render={<Button type="button" variant="outline" />}>閉じる</DialogClose>
        {/* 成功の後は確定のボタンを消す (二重に送って CONFLICT にしない) */}
        {!done && (
          <Button type="submit" disabled={pending}>
            {SUBMIT[kind]}
          </Button>
        )}
      </DialogFooter>
    </form>
  );
}

/**
 * 結果の告知の領域。中身より先に置いておき (後から差し込むと読み上げられないことがある)、結果が出たらここへフォーカスを
 * 移す (確定のボタンが消えてフォーカスの行き場が無くなるため)。
 */
function ResultRegion({ active, children }: { active: boolean; children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (active) ref.current?.focus();
  }, [active]);
  return (
    <div ref={ref} role="status" tabIndex={-1} data-testid="action-result" className="outline-none">
      {children}
    </div>
  );
}
