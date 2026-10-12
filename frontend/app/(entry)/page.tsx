import { EntryCard } from "@/components/entry-shell";
import { ErrorNotice } from "@/components/error-notice";
import { LoginForm } from "@/components/login-form";

// ログインの画面。資格情報は Next のサーバーが Rails の POST /session へ送り、ブラウザは Rails を直接呼ばない
export default async function LoginPage({ searchParams }: PageProps<"/">) {
  const expired = (await searchParams).expired === "1";
  return (
    <EntryCard className="space-y-5">
      <div>
        <h1>受発注・在庫・請求デモ</h1>
        <p className="text-muted-foreground mt-3 text-sm leading-relaxed">
          機械部品メーカー「青嵐精機工業」と、取引先の組立メーカー 2 社（どれも架空）の受発注・在庫・出荷・検収・請求を、
          受注側と発注側の両方の画面で体験できます。
        </p>
      </div>
      {expired && (
        <ErrorNotice data-testid="session-expired">セッションが切れました。もう一度ログインしてください。</ErrorNotice>
      )}
      <LoginForm />
    </EntryCard>
  );
}
