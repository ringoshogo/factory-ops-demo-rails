"use server";

import { redirect } from "next/navigation";
import { INTEGER_MESSAGE, parseInt32 } from "@/lib/form-input";
import type { FormState } from "@/lib/form-state";
import {
  CloseBillingPeriodDocument,
  DiscardDraftInvoiceDocument,
  IssueInvoiceDocument,
  SetBillingTermDocument,
} from "@/lib/graphql/generated";
import { mutate } from "@/lib/graphql/request";
import { settle } from "@/lib/graphql/user-errors";

const BILLING = "/supplier/billing";
const INVOICES = "/supplier/invoices";

const str = (form: FormData, key: string) => String(form.get(key) ?? "").trim();

/**
 * 取引先ごとの締め日を設定する。締め日の範囲 (1〜28 か月末の 31) は API が確かめ、画面では Int に送れるかだけを確かめる。
 * 送れない値は、API の INVALID_INPUT と同じく入力欄の下に出す。
 */
export async function setBillingTerm(_prev: FormState, form: FormData): Promise<FormState> {
  const closingDay = parseInt32(str(form, "closingDay"));
  if (closingDay === null) {
    return { status: "error", fieldErrors: { closingDay: INTEGER_MESSAGE } };
  }
  const result = await mutate(SetBillingTermDocument, {
    input: { customerTenantId: str(form, "customerTenantId"), closingDay },
  });
  return settle(result, (d) => d.setBillingTerm, [BILLING]);
}

/** 取引先の締め日までの未請求の明細を、下書きの請求書にまとめる。成功したら請求書の詳細へ移る。 */
export async function closeBillingPeriod(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(CloseBillingPeriodDocument, {
    input: { customerTenantId: str(form, "customerTenantId"), closingDate: str(form, "closingDate") },
  });
  const state = settle(result, (d) => d.closeBillingPeriod, [BILLING, INVOICES]);
  const invoiceId = result.kind === "ok" ? result.data.closeBillingPeriod.invoice?.id : undefined;
  if (state.status === "ok" && invoiceId) redirect(`${INVOICES}/${invoiceId}`);
  return state;
}

/** 下書きの請求書を破棄する。明細は未請求に戻るので、請求の締めの画面へ移る。 */
export async function discardDraftInvoice(_prev: FormState, form: FormData): Promise<FormState> {
  const result = await mutate(DiscardDraftInvoiceDocument, { input: { invoiceId: str(form, "invoiceId") } });
  const state = settle(result, (d) => d.discardDraftInvoice, [BILLING, INVOICES]);
  if (state.status === "ok") redirect(BILLING);
  return state;
}

/** 下書きの請求書を確定し、請求書番号を振る。確定した請求書は書き換えられない。 */
export async function issueInvoice(_prev: FormState, form: FormData): Promise<FormState> {
  const invoiceId = str(form, "invoiceId");
  const result = await mutate(IssueInvoiceDocument, { input: { invoiceId } });
  return settle(result, (d) => d.issueInvoice, [INVOICES, `${INVOICES}/${invoiceId}`]);
}
