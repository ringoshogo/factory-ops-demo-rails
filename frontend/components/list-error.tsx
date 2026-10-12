import { ErrorNotice } from "@/components/error-notice";

/** 一覧の上に出す API のエラー (`data-testid="list-error"`)。文言は API のものをそのまま渡す。 */
export function ListError({ children }: { children: React.ReactNode }) {
  return <ErrorNotice data-testid="list-error">{children}</ErrorNotice>;
}
