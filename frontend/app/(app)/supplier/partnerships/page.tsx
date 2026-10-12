import { DateText } from "@/components/date-text";
import { ListError } from "@/components/list-error";
import { PageHeader } from "@/components/page-header";
import { EstablishDialog, PermissionToggle, RevokeDialog } from "@/components/partnership-forms";
import { StatusBadge } from "@/components/status-badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { SupplierPartnershipsDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { PARTNERSHIP_STATUS, PERMISSION_LABEL, PERMISSION_ORDER } from "@/lib/statuses";
import { isAdmin } from "@/lib/viewer";

// 取引関係。受注側が、発注側の相手ごとに取引関係を結び、カタログ・発注・出荷の参照の権限を付与する。
// 変える操作は管理者だけが行う (docs/architecture/graphql-schema.md「役割による制限」)
export default async function PartnershipsPage() {
  const [result, admin] = await Promise.all([query(SupplierPartnershipsDocument), isAdmin()]);
  if (result.kind !== "ok") {
    return (
      <section className="space-y-4">
        <PageHeader title="取引関係" />
        <ListError>{result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}</ListError>
      </section>
    );
  }
  const { partnerships, dashboard } = result.data.supplier;
  // 有効な関係を先に、それぞれ取引先の名前の順に並べる。一覧は全件を 1 回で返すので、画面で並べても件数とずれない
  const rows = [...partnerships].sort(
    (a, b) => Number(a.status !== "ACTIVE") - Number(b.status !== "ACTIVE") || a.buyer.name.localeCompare(b.buyer.name, "ja"),
  );

  return (
    <section className="space-y-4">
      <PageHeader title="取引関係">{admin && <EstablishDialog />}</PageHeader>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>取引先</TableHead>
              <TableHead>状況</TableHead>
              <TableHead>権限</TableHead>
              <TableHead>失効日時</TableHead>
              {admin && <TableHead>操作</TableHead>}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && (
              <TableRow data-testid="empty-row">
                <TableCell colSpan={admin ? 5 : 4} className="text-muted-foreground py-8 text-center">
                  取引関係はまだありません
                </TableCell>
              </TableRow>
            )}
            {rows.map((p) => {
              const active = p.status === "ACTIVE";
              return (
                <TableRow key={p.id} data-testid="list-row" data-status={p.status}>
                  <TableCell truncate="wide">{p.buyer.name}</TableCell>
                  <TableCell>
                    <StatusBadge style={PARTNERSHIP_STATUS[p.status]} value={p.status} />
                  </TableCell>
                  <TableCell className="py-2">
                    <span data-testid="permissions" className="text-muted-foreground text-[13px] whitespace-normal">
                      {p.permissions.length === 0
                        ? "なし"
                        : PERMISSION_ORDER.filter((perm) => p.permissions.includes(perm))
                            .map((perm) => PERMISSION_LABEL[perm])
                            .join("・")}
                    </span>
                    {admin && active && (
                      <div className="mt-1.5 flex flex-wrap gap-1.5">
                        {PERMISSION_ORDER.map((perm) => (
                          <PermissionToggle
                            key={perm}
                            partnershipId={p.id}
                            permission={perm}
                            granted={p.permissions.includes(perm)}
                          />
                        ))}
                      </div>
                    )}
                  </TableCell>
                  <TableCell>
                    <DateText iso={p.revokedAt} businessDate={dashboard.businessDate} withTime />
                  </TableCell>
                  {admin && (
                    <TableCell>
                      {active ? (
                        <RevokeDialog partnershipId={p.id} buyerName={p.buyer.name} />
                      ) : (
                        <span className="text-muted-foreground text-sm">—</span>
                      )}
                    </TableCell>
                  )}
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
    </section>
  );
}
