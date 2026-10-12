import { ErrorNotice } from "@/components/error-notice";
import type { FormState } from "@/lib/form-state";

/** フォームの上に出す文言。成功や未送信のときは何も描かない。 */
export function FormError({ state }: { state: FormState }) {
  if (state.status !== "error" || !state.message) return null;
  return <ErrorNotice data-testid="form-error">{state.message}</ErrorNotice>;
}

/** 入力欄の下に出す文言。鍵は UserError の path を `.` でつないだもの。 */
export function FieldError({ state, name }: { state: FormState; name: string }) {
  const message = state.fieldErrors?.[name];
  if (!message) return null;
  return (
    <p data-testid="field-error" className="text-destructive text-[13px]">
      {message}
    </p>
  );
}
