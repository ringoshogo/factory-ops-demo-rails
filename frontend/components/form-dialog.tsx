"use client";

import { useActionState, useState, type ReactNode } from "react";
import { FormError } from "@/components/form-errors";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DIALOG_FORM,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { IDLE, type FormState } from "@/lib/form-state";

type Action = (prev: FormState, form: FormData) => Promise<FormState>;

/**
 * 押すとダイアログを開き、中のフォームを server action で送るボタン。成功したら閉じ、失敗したら開いたまま文言を出す
 * (閉じると入力し直しになる)。フォームは開くたびに key を変えて作り直し、前に開いたときの失敗の文言を持ち越さない。
 * `children` は送る結果を受け取って入力欄を描く関数で、入力欄の下の文言 (FieldError) に結果を渡せる。
 */
export function FormDialog({
  label,
  title,
  description,
  action,
  submitLabel,
  variant = "default",
  size = "default",
  children,
}: {
  label: ReactNode;
  title: string;
  description?: ReactNode;
  action: Action;
  submitLabel: string;
  variant?: "default" | "outline" | "ghost" | "destructive";
  size?: "default" | "sm";
  children: (state: FormState) => ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const [formKey, setFormKey] = useState(0);

  function openDialog(next: boolean) {
    if (next) setFormKey((n) => n + 1);
    setOpen(next);
  }

  return (
    <>
      <Button type="button" variant={variant} size={size} onClick={() => openDialog(true)}>
        {label}
      </Button>
      <Dialog open={open} onOpenChange={openDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{title}</DialogTitle>
            {description && <DialogDescription>{description}</DialogDescription>}
          </DialogHeader>
          <DialogForm key={formKey} action={action} submitLabel={submitLabel} onDone={() => setOpen(false)}>
            {children}
          </DialogForm>
        </DialogContent>
      </Dialog>
    </>
  );
}

function DialogForm({
  action,
  submitLabel,
  onDone,
  children,
}: {
  action: Action;
  submitLabel: string;
  onDone: () => void;
  children: (state: FormState) => ReactNode;
}) {
  // 閉じる判断は action の結果を受けたその場で行う。結果を effect で見て閉じると、描画の副作用で状態を書くことになる
  const [state, submit, pending] = useActionState(async (prev: FormState, form: FormData) => {
    const next = await action(prev, form);
    if (next.status === "ok") onDone();
    return next;
  }, IDLE);

  return (
    <form action={submit} className={DIALOG_FORM}>
      <DialogBody>
        {children(state)}
        <FormError state={state} />
      </DialogBody>
      <DialogFooter>
        <Button type="submit" disabled={pending}>
          {submitLabel}
        </Button>
      </DialogFooter>
    </form>
  );
}

/**
 * 確かめずに送る 1 つのボタン (公開の切り替え・権限の付与と撤回)。隠し項目だけを持つフォームを送り、失敗したら
 * ボタンの下に文言を出す。
 */
export function ActionButton({
  action,
  fields,
  label,
  ariaLabel,
  variant = "outline",
}: {
  action: Action;
  fields: Record<string, string>;
  label: string;
  /** 見た目の文字が記号を含むときの、読み上げと検索に使う名前 */
  ariaLabel?: string;
  variant?: "default" | "outline" | "ghost";
}) {
  const [state, submit, pending] = useActionState(action, IDLE);
  return (
    <form action={submit} className="inline-flex flex-col items-start gap-1">
      {Object.entries(fields).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      <Button type="submit" size="sm" variant={variant} disabled={pending} aria-label={ariaLabel}>
        {label}
      </Button>
      {state.status === "error" && (
        <span data-testid="row-error" className="text-destructive max-w-60 text-[13px] whitespace-normal">
          {state.message ?? Object.values(state.fieldErrors ?? {}).join(" ")}
        </span>
      )}
    </form>
  );
}

/** ダイアログの入力欄の 1 行 (ラベル・入力欄・欄の下の文言)。 */
export function FieldRow({ id, label, children, error }: { id: string; label: string; children: ReactNode; error?: ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{label}</Label>
      {children}
      {error}
    </div>
  );
}
