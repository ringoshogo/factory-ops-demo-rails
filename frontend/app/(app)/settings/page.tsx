import { ErrorNotice } from "@/components/error-notice";
import { PageHeader } from "@/components/page-header";
import { ViewerSettingsDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";

// 自社の情報。取引用コードは admin にだけ返る (member には null)。取引用コードを知った者は受注側として
// 取引関係を結べるので、画面でも admin にだけ見せる (docs/architecture/graphql-schema.md「役割による制限」)
export default async function SettingsPage() {
  const result = await query(ViewerSettingsDocument);
  if (result.kind !== "ok") {
    return (
      <section className="space-y-5">
        <PageHeader title="自社の情報" />
        <ErrorNotice data-testid="detail-error">
          {result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}
        </ErrorNotice>
      </section>
    );
  }
  const viewer = result.data.viewer;
  const admin = viewer.role === "admin";

  return (
    <section className="space-y-6">
      <PageHeader title="自社の情報" />
      <dl className="grid max-w-2xl grid-cols-[10rem_1fr] gap-x-6 gap-y-3 text-sm">
        <dt className="text-muted-foreground">自社</dt>
        <dd data-testid="settings-tenant">{viewer.tenant.name}</dd>
        <dt className="text-muted-foreground">ユーザー</dt>
        <dd>{viewer.name}</dd>
        <dt className="text-muted-foreground">メールアドレス</dt>
        <dd>{viewer.email}</dd>
        <dt className="text-muted-foreground">役割</dt>
        <dd>{admin ? "管理者" : "担当者"}</dd>
      </dl>

      <div className="max-w-2xl space-y-2">
        <h2 className="text-base font-semibold">取引用コード</h2>
        <p className="text-muted-foreground text-[13px] leading-relaxed">
          受注側の会社に、画面の外 (メールや書面) で伝える値です。受注側はこのコードを入れて、自社と取引関係を結びます。
          推測できない値なので、取引を始める相手にだけ伝えてください。
        </p>
        {admin && viewer.partnerCode ? (
          <code
            data-testid="partner-code"
            className="bg-muted rounded-control inline-block px-3 py-2 text-sm break-all"
          >
            {viewer.partnerCode}
          </code>
        ) : (
          <p data-testid="partner-code-hidden" className="text-muted-foreground text-sm">
            管理者だけが見られます。
          </p>
        )}
      </div>
    </section>
  );
}
