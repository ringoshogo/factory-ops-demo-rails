import { notFound } from "next/navigation";
import { ErrorNotice } from "@/components/error-notice";
import { SalesOrderDetail } from "@/components/sales-order-detail";
import { SupplierSalesOrderDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { isAdmin } from "@/lib/viewer";

// 受注詳細。ID で引いて返らなければ見つからない画面にし、無いのか他社の受注なのかを言い分けない
export default async function SalesOrderDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [result, admin] = await Promise.all([query(SupplierSalesOrderDocument, { id }), isAdmin()]);
  if (result.kind !== "ok") {
    return (
      <ErrorNotice data-testid="detail-error">{result.kind === "error" ? result.message : UNREACHABLE_MESSAGE}</ErrorNotice>
    );
  }
  const order = result.data.supplier.salesOrder;
  if (!order) notFound();
  return <SalesOrderDetail order={order} businessDate={result.data.supplier.dashboard.businessDate} admin={admin} />;
}
