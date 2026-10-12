import { cn } from "cn";

/**
 * 画面の見出し 1 の枠 (仕様 cycle-03 §3 共通部品「見出し」)。見出しの下に 20px の余白と
 * --divider の下線を引く。右側 (`children`) には画面ごとの操作や業務日付を置く。
 *
 * 業務 6 画面と受注登録・受注詳細が使う。ログイン画面と見つからない画面はカードの中に
 * 見出しを置くので使わない。`description` は見出しの下に置く (ダッシュボードの業務日付)。
 *
 * すぐ下にタブ (`LinkTabs`) を置く画面 (受注一覧・在庫) は `divider={false}` にする。見本
 * (orders.html) どおり、タブの並びの下線が見出しの区切りを兼ね、線を 2 本重ねない。
 */
export function PageHeader({
  title,
  description,
  children,
  divider = true,
}: {
  title: React.ReactNode;
  /** 見出しの下に置く補助の文字 (ダッシュボードの業務日付)。 */
  description?: React.ReactNode;
  children?: React.ReactNode;
  /** 見出しの下の余白と線。タブを続ける画面では false。 */
  divider?: boolean;
}) {
  return (
    <div
      data-slot="page-header"
      className={cn(
        "flex flex-wrap items-center justify-between gap-3",
        divider && "border-divider border-b pb-5",
      )}
    >
      {description ? (
        <div>
          <h1>{title}</h1>
          <p className="text-muted-foreground mt-0.5 text-[13px]">{description}</p>
        </div>
      ) : (
        <h1>{title}</h1>
      )}
      {children}
    </div>
  );
}
