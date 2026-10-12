/** Internal type. DO NOT USE DIRECTLY. */
type Exact<T extends { [key: string]: unknown }> = { [K in keyof T]: T[K] };
/** Internal type. DO NOT USE DIRECTLY. */
export type Incremental<T> = T | { [P in keyof T]?: P extends ' $fragmentName' | '__typename' ? T[P] : never };
import type { TypedDocumentNode as DocumentNode } from '@graphql-typed-document-node/core';
export type ItemFilter = {
  /** 前後の空白を除いて、品目コードか品目名に含む品目に絞る。大文字と小文字を区別せず、% と _ は文字として扱う。空なら絞らない。100 文字まで */
  keyword?: string | null | undefined;
};

export type ItemOrder = {
  direction: OrderDirection;
  field: ItemOrderField;
};

export type ItemOrderField =
  /** 品目コード */
  | 'CODE'
  /** 品目名 */
  | 'NAME';

export type OrderDirection =
  /** 昇順 */
  | 'ASC'
  /** 降順 */
  | 'DESC';

export type PartnershipPermission =
  /** 発注を登録できる */
  | 'PLACE_ORDERS'
  /** 経路 1（カタログ）を開く */
  | 'VIEW_CATALOG'
  /** 経路 3（自社の発注に連結した出荷）を開く */
  | 'VIEW_SHIPMENTS';

export type PartnershipStatus =
  | 'ACTIVE'
  | 'REVOKED';

export type PurchaseOrderFilter = {
  orderDateFrom?: string | null | undefined;
  orderDateTo?: string | null | undefined;
  /** 状況。空の配列は 0 件を返し、省くか null なら絞らない。取消依頼中は状況ではないので含めない */
  statuses?: Array<PurchaseOrderStatus> | null | undefined;
  supplierTenantId?: string | number | null | undefined;
};

export type PurchaseOrderOrder = {
  direction: OrderDirection;
  field: PurchaseOrderOrderField;
};

export type PurchaseOrderOrderField =
  /** 希望納期 */
  | 'DESIRED_DELIVERY_ON'
  /** 発注日 */
  | 'ORDER_DATE'
  /** 発注番号 */
  | 'ORDER_NO';

export type PurchaseOrderStatus =
  /** 受注済 */
  | 'ACCEPTED'
  /** 受注側で確認中 */
  | 'AWAITING_SUPPLIER_CONFIRMATION'
  /** 取消済み */
  | 'CANCELLED'
  /** 入荷予定 */
  | 'INBOUND'
  /** 検収済 */
  | 'INSPECTED'
  /** 送信済み */
  | 'SENT'
  /** 受注側により取消 */
  | 'SUPPLIER_CANCELLED';

export type SalesOrderFilter = {
  customerTenantId?: string | number | null | undefined;
  orderDateFrom?: string | null | undefined;
  orderDateTo?: string | null | undefined;
  /** 状況。空の配列は 0 件を返し、省くか null なら絞らない。取消審査中は状況ではないので含めない */
  statuses?: Array<SalesOrderStatus> | null | undefined;
};

export type SalesOrderOrder = {
  direction: OrderDirection;
  field: SalesOrderOrderField;
};

export type SalesOrderOrderField =
  /** 希望納期 */
  | 'DUE_DATE'
  /** 受注日 */
  | 'ORDER_DATE'
  /** 受注番号 */
  | 'ORDER_NO';

export type SalesOrderStatus =
  /** 引当済 */
  | 'ALLOCATED'
  /** 品番照合待ち */
  | 'AWAITING_PART_MATCH'
  /** 取消済 */
  | 'CANCELLED'
  /** 検収済 */
  | 'INSPECTED'
  /** 一部引当 */
  | 'PARTIALLY_ALLOCATED'
  /** 受注済 */
  | 'RECEIVED'
  /** 出荷済 */
  | 'SHIPPED';

export type ShipmentRequestFilter = {
  /** 状況。空の配列は 0 件を返し、省くか null なら絞らない */
  statuses?: Array<ShipmentRequestStatus> | null | undefined;
};

export type ShipmentRequestOrder = {
  direction: OrderDirection;
  field: ShipmentRequestOrderField;
};

export type ShipmentRequestOrderField =
  /** 出荷期限 */
  | 'DUE_DATE';

export type ShipmentRequestStatus =
  /** 取消済 */
  | 'CANCELLED'
  /** 出荷指示済 */
  | 'INSTRUCTED'
  /** 出荷停止中 */
  | 'ON_HOLD'
  /** 出荷待ち */
  | 'READY'
  /** 出荷済 */
  | 'SHIPPED';

export type StockFilter = {
  /** 真なら、ダッシュボードの stocksBelowSafetyStock と同じ条件（有効在庫が安全在庫より小さい）で絞る。偽か省けば絞らない */
  belowSafetyStock?: boolean | null | undefined;
};

export type StockMovementFilter = {
  /** 移動の種類。空の配列は 0 件を返し、省くか null なら絞らない */
  types?: Array<StockMovementType> | null | undefined;
};

export type StockMovementType =
  /** 引当 */
  | 'ALLOCATE'
  /** 引当の解除 */
  | 'DEALLOCATE'
  /** 入庫 */
  | 'INBOUND'
  /** 出庫 */
  | 'OUTBOUND'
  /** 出荷 */
  | 'SHIP';

export type StockOrder = {
  direction: OrderDirection;
  field: StockOrderField;
};

export type StockOrderField =
  /** 引当 */
  | 'ALLOCATED'
  /** 有効在庫（現在庫 - 引当） */
  | 'AVAILABLE'
  /** 現在庫 */
  | 'ON_HAND'
  /** 安全在庫 */
  | 'SAFETY_STOCK';

export type BuyerPurchaseOrdersQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  orderBy?: PurchaseOrderOrder | null | undefined;
  filter?: PurchaseOrderFilter | null | undefined;
}>;


export type BuyerPurchaseOrdersQuery = { buyer: { purchaseOrders: { totalCount: number, nodes: Array<{ id: string, orderNo: string, orderDate: string, desiredDeliveryOn: string | null, status: PurchaseOrderStatus, supplier: { id: string, name: string }, lines: Array<{ id: string, partNumber: string, quantity: number, confirmedItemName: string | null, confirmedUnitPrice: string | null }>, inboundShipments: Array<{ id: string, shippedOn: string }>, supplierShipments: Array<{ shippedOn: string }> } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } };

export type BuyerSupplierCatalogQueryVariables = Exact<{
  supplierTenantId: string | number;
  first?: number | null | undefined;
  after?: string | null | undefined;
}>;


export type BuyerSupplierCatalogQuery = { buyer: { supplier: { supplier: { id: string, name: string }, catalog: { nodes: Array<{ code: string, name: string, unit: string, unitPrice: string, taxRatePercent: number } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } | null } };

export type BuyerSuppliersQueryVariables = Exact<{ [key: string]: never; }>;


export type BuyerSuppliersQuery = { buyer: { suppliers: Array<{ permissions: Array<PartnershipPermission>, supplier: { id: string, name: string } }> } };

export type SupplierDashboardQueryVariables = Exact<{ [key: string]: never; }>;


export type SupplierDashboardQuery = { supplier: { dashboard: { businessDate: string, unbilledTotal: string, salesOrderCounts: Array<{ status: SalesOrderStatus, count: number }>, stocksBelowSafetyStock: Array<{ onHand: number, allocated: number, available: number, safetyStock: number, item: { id: string, code: string, name: string, unit: string } }>, shipmentRequestsDueSoon: Array<{ id: string, dueDate: string | null, status: ShipmentRequestStatus, salesOrder: { id: string, orderNo: string }, customer: { id: string, name: string } }> } } };

export type SupplierItemsQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  orderBy?: ItemOrder | null | undefined;
  filter?: ItemFilter | null | undefined;
}>;


export type SupplierItemsQuery = { supplier: { items: { totalCount: number, nodes: Array<{ id: string, code: string, name: string, unit: string, unitPrice: string, taxRatePercent: number, published: boolean, stock: { onHand: number, allocated: number, available: number, safetyStock: number, belowSafetyStock: boolean } | null } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } };

export type SupplierPartMappingsQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  customerTenantId?: string | number | null | undefined;
}>;


export type SupplierPartMappingsQuery = { supplier: { partMappings: { nodes: Array<{ id: string, customerPartNumber: string, customer: { id: string, name: string }, item: { id: string, code: string, name: string } } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } };

export type SupplierPartnershipsQueryVariables = Exact<{ [key: string]: never; }>;


export type SupplierPartnershipsQuery = { supplier: { partnerships: Array<{ id: string, status: PartnershipStatus, revokedAt: string | null, permissions: Array<PartnershipPermission>, buyer: { id: string, name: string } }> } };

export type SupplierSalesOrdersQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  orderBy?: SalesOrderOrder | null | undefined;
  filter?: SalesOrderFilter | null | undefined;
  allFilter?: SalesOrderFilter | null | undefined;
  openFilter?: SalesOrderFilter | null | undefined;
  shippedFilter?: SalesOrderFilter | null | undefined;
  inspectedFilter?: SalesOrderFilter | null | undefined;
  cancelledFilter?: SalesOrderFilter | null | undefined;
}>;


export type SupplierSalesOrdersQuery = { supplier: { dashboard: { businessDate: string }, partnerships: Array<{ id: string, buyer: { id: string, name: string } }>, salesOrders: { totalCount: number, nodes: Array<{ id: string, orderNo: string, orderDate: string, dueDate: string | null, status: SalesOrderStatus, cancellationReviewPending: boolean, customer: { id: string, name: string }, lines: Array<{ id: string, customerPartNumber: string, itemName: string | null, quantity: number, allocatedQuantity: number, unitPrice: string | null, taxRatePercent: number | null }>, shipmentRequest: { id: string, status: ShipmentRequestStatus } | null } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } }, all: { totalCount: number }, open: { totalCount: number }, shipped: { totalCount: number }, inspected: { totalCount: number }, cancelled: { totalCount: number } } };

export type SupplierShipmentRequestsQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  orderBy?: ShipmentRequestOrder | null | undefined;
  filter?: ShipmentRequestFilter | null | undefined;
}>;


export type SupplierShipmentRequestsQuery = { supplier: { shipmentRequests: { totalCount: number, nodes: Array<{ id: string, dueDate: string | null, status: ShipmentRequestStatus, salesOrder: { id: string, orderNo: string }, customer: { id: string, name: string }, lines: Array<{ id: string, quantity: number }>, instruction: { id: string, plannedDate: string } | null } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } };

export type SupplierStockMovementsQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  itemId?: string | number | null | undefined;
  filter?: StockMovementFilter | null | undefined;
}>;


export type SupplierStockMovementsQuery = { supplier: { stockMovements: { totalCount: number, nodes: Array<{ id: string, type: StockMovementType, quantity: number, reason: string | null, createdAt: string, item: { id: string, code: string, name: string } } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } };

export type SupplierStocksQueryVariables = Exact<{
  first?: number | null | undefined;
  after?: string | null | undefined;
  orderBy?: StockOrder | null | undefined;
  filter?: StockFilter | null | undefined;
}>;


export type SupplierStocksQuery = { supplier: { stocks: { totalCount: number, nodes: Array<{ onHand: number, allocated: number, available: number, safetyStock: number, belowSafetyStock: boolean, item: { id: string, code: string, name: string, unit: string } } | null> | null, pageInfo: { hasNextPage: boolean, endCursor: string | null } } } };

export type ViewerLandingQueryVariables = Exact<{ [key: string]: never; }>;


export type ViewerLandingQuery = { supplier: { partnerships: Array<{ id: string }> } };

export type ViewerShellQueryVariables = Exact<{ [key: string]: never; }>;


export type ViewerShellQuery = { viewer: { id: string, name: string, role: string, tenant: { id: string, name: string } } };


export const BuyerPurchaseOrdersDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"BuyerPurchaseOrders"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"PurchaseOrderOrder"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"filter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"PurchaseOrderFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"buyer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"purchaseOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"orderBy"},"value":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}}},{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"filter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}},{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"orderNo"}},{"kind":"Field","name":{"kind":"Name","value":"orderDate"}},{"kind":"Field","name":{"kind":"Name","value":"desiredDeliveryOn"}},{"kind":"Field","name":{"kind":"Name","value":"status"}},{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"lines"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"partNumber"}},{"kind":"Field","name":{"kind":"Name","value":"quantity"}},{"kind":"Field","name":{"kind":"Name","value":"confirmedItemName"}},{"kind":"Field","name":{"kind":"Name","value":"confirmedUnitPrice"}}]}},{"kind":"Field","name":{"kind":"Name","value":"inboundShipments"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"shippedOn"}}]}},{"kind":"Field","name":{"kind":"Name","value":"supplierShipments"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"shippedOn"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]} as unknown as DocumentNode<BuyerPurchaseOrdersQuery, BuyerPurchaseOrdersQueryVariables>;
export const BuyerSupplierCatalogDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"BuyerSupplierCatalog"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"supplierTenantId"}},"type":{"kind":"NonNullType","type":{"kind":"NamedType","name":{"kind":"Name","value":"ID"}}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"buyer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"supplierTenantId"},"value":{"kind":"Variable","name":{"kind":"Name","value":"supplierTenantId"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"catalog"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"code"}},{"kind":"Field","name":{"kind":"Name","value":"name"}},{"kind":"Field","name":{"kind":"Name","value":"unit"}},{"kind":"Field","name":{"kind":"Name","value":"unitPrice"}},{"kind":"Field","name":{"kind":"Name","value":"taxRatePercent"}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]}}]} as unknown as DocumentNode<BuyerSupplierCatalogQuery, BuyerSupplierCatalogQueryVariables>;
export const BuyerSuppliersDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"BuyerSuppliers"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"buyer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"suppliers"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"permissions"}}]}}]}}]}}]} as unknown as DocumentNode<BuyerSuppliersQuery, BuyerSuppliersQueryVariables>;
export const SupplierDashboardDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierDashboard"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"dashboard"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"businessDate"}},{"kind":"Field","name":{"kind":"Name","value":"salesOrderCounts"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"status"}},{"kind":"Field","name":{"kind":"Name","value":"count"}}]}},{"kind":"Field","name":{"kind":"Name","value":"stocksBelowSafetyStock"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"onHand"}},{"kind":"Field","name":{"kind":"Name","value":"allocated"}},{"kind":"Field","name":{"kind":"Name","value":"available"}},{"kind":"Field","name":{"kind":"Name","value":"safetyStock"}},{"kind":"Field","name":{"kind":"Name","value":"item"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"code"}},{"kind":"Field","name":{"kind":"Name","value":"name"}},{"kind":"Field","name":{"kind":"Name","value":"unit"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"shipmentRequestsDueSoon"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"dueDate"}},{"kind":"Field","name":{"kind":"Name","value":"status"}},{"kind":"Field","name":{"kind":"Name","value":"salesOrder"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"orderNo"}}]}},{"kind":"Field","name":{"kind":"Name","value":"customer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"unbilledTotal"}}]}}]}}]}}]} as unknown as DocumentNode<SupplierDashboardQuery, SupplierDashboardQueryVariables>;
export const SupplierItemsDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierItems"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"ItemOrder"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"filter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"ItemFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"items"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"orderBy"},"value":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}}},{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"filter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}},{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"code"}},{"kind":"Field","name":{"kind":"Name","value":"name"}},{"kind":"Field","name":{"kind":"Name","value":"unit"}},{"kind":"Field","name":{"kind":"Name","value":"unitPrice"}},{"kind":"Field","name":{"kind":"Name","value":"taxRatePercent"}},{"kind":"Field","name":{"kind":"Name","value":"published"}},{"kind":"Field","name":{"kind":"Name","value":"stock"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"onHand"}},{"kind":"Field","name":{"kind":"Name","value":"allocated"}},{"kind":"Field","name":{"kind":"Name","value":"available"}},{"kind":"Field","name":{"kind":"Name","value":"safetyStock"}},{"kind":"Field","name":{"kind":"Name","value":"belowSafetyStock"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]} as unknown as DocumentNode<SupplierItemsQuery, SupplierItemsQueryVariables>;
export const SupplierPartMappingsDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierPartMappings"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"customerTenantId"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"ID"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"partMappings"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"customerTenantId"},"value":{"kind":"Variable","name":{"kind":"Name","value":"customerTenantId"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"customerPartNumber"}},{"kind":"Field","name":{"kind":"Name","value":"customer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"item"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"code"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]} as unknown as DocumentNode<SupplierPartMappingsQuery, SupplierPartMappingsQueryVariables>;
export const SupplierPartnershipsDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierPartnerships"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"partnerships"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"status"}},{"kind":"Field","name":{"kind":"Name","value":"revokedAt"}},{"kind":"Field","name":{"kind":"Name","value":"buyer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"permissions"}}]}}]}}]}}]} as unknown as DocumentNode<SupplierPartnershipsQuery, SupplierPartnershipsQueryVariables>;
export const SupplierSalesOrdersDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierSalesOrders"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderOrder"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"filter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderFilter"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"allFilter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderFilter"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"openFilter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderFilter"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"shippedFilter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderFilter"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"inspectedFilter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderFilter"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"cancelledFilter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"SalesOrderFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"dashboard"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"businessDate"}}]}},{"kind":"Field","name":{"kind":"Name","value":"partnerships"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"buyer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"salesOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"orderBy"},"value":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}}},{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"filter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}},{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"orderNo"}},{"kind":"Field","name":{"kind":"Name","value":"orderDate"}},{"kind":"Field","name":{"kind":"Name","value":"dueDate"}},{"kind":"Field","name":{"kind":"Name","value":"status"}},{"kind":"Field","name":{"kind":"Name","value":"cancellationReviewPending"}},{"kind":"Field","name":{"kind":"Name","value":"customer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"lines"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"customerPartNumber"}},{"kind":"Field","name":{"kind":"Name","value":"itemName"}},{"kind":"Field","name":{"kind":"Name","value":"quantity"}},{"kind":"Field","name":{"kind":"Name","value":"allocatedQuantity"}},{"kind":"Field","name":{"kind":"Name","value":"unitPrice"}},{"kind":"Field","name":{"kind":"Name","value":"taxRatePercent"}}]}},{"kind":"Field","name":{"kind":"Name","value":"shipmentRequest"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"status"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}},{"kind":"Field","alias":{"kind":"Name","value":"all"},"name":{"kind":"Name","value":"salesOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"allFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}}]}},{"kind":"Field","alias":{"kind":"Name","value":"open"},"name":{"kind":"Name","value":"salesOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"openFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}}]}},{"kind":"Field","alias":{"kind":"Name","value":"shipped"},"name":{"kind":"Name","value":"salesOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"shippedFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}}]}},{"kind":"Field","alias":{"kind":"Name","value":"inspected"},"name":{"kind":"Name","value":"salesOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"inspectedFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}}]}},{"kind":"Field","alias":{"kind":"Name","value":"cancelled"},"name":{"kind":"Name","value":"salesOrders"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"cancelledFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}}]}}]}}]}}]} as unknown as DocumentNode<SupplierSalesOrdersQuery, SupplierSalesOrdersQueryVariables>;
export const SupplierShipmentRequestsDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierShipmentRequests"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"ShipmentRequestOrder"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"filter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"ShipmentRequestFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"shipmentRequests"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"orderBy"},"value":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}}},{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"filter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}},{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"dueDate"}},{"kind":"Field","name":{"kind":"Name","value":"status"}},{"kind":"Field","name":{"kind":"Name","value":"salesOrder"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"orderNo"}}]}},{"kind":"Field","name":{"kind":"Name","value":"customer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}},{"kind":"Field","name":{"kind":"Name","value":"lines"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"quantity"}}]}},{"kind":"Field","name":{"kind":"Name","value":"instruction"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"plannedDate"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]} as unknown as DocumentNode<SupplierShipmentRequestsQuery, SupplierShipmentRequestsQueryVariables>;
export const SupplierStockMovementsDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierStockMovements"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"itemId"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"ID"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"filter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"StockMovementFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"stockMovements"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"itemId"},"value":{"kind":"Variable","name":{"kind":"Name","value":"itemId"}}},{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"filter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}},{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"type"}},{"kind":"Field","name":{"kind":"Name","value":"quantity"}},{"kind":"Field","name":{"kind":"Name","value":"reason"}},{"kind":"Field","name":{"kind":"Name","value":"createdAt"}},{"kind":"Field","name":{"kind":"Name","value":"item"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"code"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]} as unknown as DocumentNode<SupplierStockMovementsQuery, SupplierStockMovementsQueryVariables>;
export const SupplierStocksDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"SupplierStocks"},"variableDefinitions":[{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"first"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"Int"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"after"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"String"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"StockOrder"}}},{"kind":"VariableDefinition","variable":{"kind":"Variable","name":{"kind":"Name","value":"filter"}},"type":{"kind":"NamedType","name":{"kind":"Name","value":"StockFilter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"stocks"},"arguments":[{"kind":"Argument","name":{"kind":"Name","value":"first"},"value":{"kind":"Variable","name":{"kind":"Name","value":"first"}}},{"kind":"Argument","name":{"kind":"Name","value":"after"},"value":{"kind":"Variable","name":{"kind":"Name","value":"after"}}},{"kind":"Argument","name":{"kind":"Name","value":"orderBy"},"value":{"kind":"Variable","name":{"kind":"Name","value":"orderBy"}}},{"kind":"Argument","name":{"kind":"Name","value":"filter"},"value":{"kind":"Variable","name":{"kind":"Name","value":"filter"}}}],"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"totalCount"}},{"kind":"Field","name":{"kind":"Name","value":"nodes"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"onHand"}},{"kind":"Field","name":{"kind":"Name","value":"allocated"}},{"kind":"Field","name":{"kind":"Name","value":"available"}},{"kind":"Field","name":{"kind":"Name","value":"safetyStock"}},{"kind":"Field","name":{"kind":"Name","value":"belowSafetyStock"}},{"kind":"Field","name":{"kind":"Name","value":"item"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"code"}},{"kind":"Field","name":{"kind":"Name","value":"name"}},{"kind":"Field","name":{"kind":"Name","value":"unit"}}]}}]}},{"kind":"Field","name":{"kind":"Name","value":"pageInfo"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"hasNextPage"}},{"kind":"Field","name":{"kind":"Name","value":"endCursor"}}]}}]}}]}}]}}]} as unknown as DocumentNode<SupplierStocksQuery, SupplierStocksQueryVariables>;
export const ViewerLandingDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"ViewerLanding"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"supplier"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"partnerships"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}}]}}]}}]}}]} as unknown as DocumentNode<ViewerLandingQuery, ViewerLandingQueryVariables>;
export const ViewerShellDocument = {"kind":"Document","definitions":[{"kind":"OperationDefinition","operation":"query","name":{"kind":"Name","value":"ViewerShell"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"viewer"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}},{"kind":"Field","name":{"kind":"Name","value":"role"}},{"kind":"Field","name":{"kind":"Name","value":"tenant"},"selectionSet":{"kind":"SelectionSet","selections":[{"kind":"Field","name":{"kind":"Name","value":"id"}},{"kind":"Field","name":{"kind":"Name","value":"name"}}]}}]}}]}}]} as unknown as DocumentNode<ViewerShellQuery, ViewerShellQueryVariables>;