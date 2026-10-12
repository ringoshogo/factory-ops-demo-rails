import { cn } from "cn";

/**
 * API の失敗・入力のエラーの文言 (状態バナー・注意書きと同じ形: 角丸 8px・--tone-danger の面と縁)。
 * 一覧の上・詳細・フォーム・ダイアログで同じ見た目にする。`data-testid` は呼び出し側が付ける。
 */
export function ErrorNotice({ className, ...props }: React.ComponentProps<"p">) {
  return (
    <p
      className={cn(
        "rounded-control border-danger-border bg-danger text-danger-foreground border px-3 py-2 text-sm",
        className,
      )}
      {...props}
    />
  );
}
