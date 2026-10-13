import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { AuditLogListQuery } from "@/lib/audit-log-list";

/**
 * 監査ログの絞り込み。文字を入れて送る形なので `<form method="get">` にする。送るとクエリ全体が置き換わり、
 * 次のページの位置 (after) も外れて 1 ページ目に戻る。
 */
export function AuditLogFilter({ q }: { q: AuditLogListQuery }) {
  return (
    <form method="get" className="flex flex-wrap items-end gap-3">
      <div className="space-y-1.5">
        <Label htmlFor="audit-action">操作</Label>
        <Input id="audit-action" name="action" defaultValue={q.action} placeholder="partnership.revoke" className="w-56" />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="audit-correlation">相関 ID</Label>
        <Input id="audit-correlation" name="correlation" defaultValue={q.correlationId} className="w-72" />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="audit-from">開始日</Label>
        <Input id="audit-from" name="from" type="date" defaultValue={q.from ?? ""} className="w-44" />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="audit-to">終了日</Label>
        <Input id="audit-to" name="to" type="date" defaultValue={q.to ?? ""} className="w-44" />
      </div>
      <Button type="submit" variant="outline">
        絞り込む
      </Button>
    </form>
  );
}
