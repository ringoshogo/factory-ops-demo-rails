import { notFound } from "next/navigation";
import { ErrorNotice } from "@/components/error-notice";
import { PurchaseOrderDetail } from "@/components/purchase-order-detail";
import { BuyerPurchaseOrderDocument } from "@/lib/graphql/generated";
import { query } from "@/lib/graphql/request";
import { UNREACHABLE_MESSAGE } from "@/lib/graphql/user-errors";
import { isAdmin } from "@/lib/viewer";

// 発注詳細。ID で引いて返らなければ、無いのか他社のものなのかを言い分けずに見つからない画面にする
export default async function PurchaseOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [result, admin] = await Promise.all([query(BuyerPurchaseOrderDocument, { id }), isAdmin()]);
  if (result.kind !== "ok") {
    return (
      <ErrorNotice data-testid="detail-error">
        {result.kind === "unreachable" ? UNREACHABLE_MESSAGE : result.message}
      </ErrorNotice>
    );
  }
  const order = result.data.buyer.purchaseOrder;
  if (!order) notFound();
  return <PurchaseOrderDetail order={order} businessDate={result.data.supplier.dashboard.businessDate} admin={admin} />;
}
