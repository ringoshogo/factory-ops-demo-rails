module Purchasing
  # 発注の進みの出来事を、状況の式（PurchaseOrderStatus）が読む発注の時刻列・入荷・検収に、取消依頼と受領請求書を足した自社の行から組み立てる
  # （docs/architecture/graphql-schema.md「発注側の視点」）。
  # 履歴の表は持たず、上書きされて時刻が残らない出来事は出さない
  module PurchaseOrderTimeline
    # 出来事の業務の順。同じ日付と時刻の出来事はこの順で並べ、日付だけの出来事（出荷・検収・請求書の受領）は、
    # 同じ日の時刻の出来事の後ろにこの順で並ぶ
    KINDS = %i[ordered part_match_pending accepted cancellation_requested cancellation_approved cancellation_rejected
      supplier_cancelled shipped inspected invoice_received].freeze
    RANKS = KINDS.each_with_index.to_h.freeze

    # orders は Scope を通した自社の発注。発注 ID ごとに、並べた PurchaseOrderTimelineEntryValue の配列を返す。
    # 全発注の出来事を 1 回の問い合わせで読む。枝ごとに引くと、発注の数ではなく出来事の種類の数だけ問い合わせが増える。
    # 承認で書く発注の cancelled_at は取消依頼の decided_at と同じ時刻なので、別の出来事にしない
    def self.for(orders)
      rows = PurchaseOrder.connection.select_all(sql(orders), "Purchasing::PurchaseOrderTimeline").cast_values
      rows.map { |order_id, owner_tenant_id, kind, occurred_at, occurred_on, row_id| [ order_id, entry(owner_tenant_id, kind, occurred_at, occurred_on), row_id ] }
        .sort_by { |_, entry, row_id| [ entry.occurred_on, entry.occurred_at ? 0 : 1, entry.occurred_at, RANKS.fetch(entry.kind), row_id ] }
        .group_by(&:first).transform_values { |grouped| grouped.map { _2 } }
    end

    # 時刻の列は UTC で読むので、日本時間（config.time_zone）にしてから日付を取る。UTC の日付のままだと、0〜9 時の出来事が前日に並ぶ
    def self.entry(owner_tenant_id, kind, occurred_at, occurred_on)
      occurred_at = occurred_at&.in_time_zone
      PurchaseOrderTimelineEntryValue.new(kind: kind.to_sym, occurred_on: occurred_at&.to_date || occurred_on, occurred_at:, owner_tenant_id:)
    end

    # 枝ごとに列の型をそろえる。型を付けない NULL は text とみなされ、ほかの枝の date・timestamp と合わずに UNION ALL が失敗する。どの枝も scoped_orders に結び、
    # 子の行は所有テナントと親の組の外部キーで発注と同じテナントに限られる。
    # 受領請求書は明細で発注に結ぶが、明細で結ぶと同じ発注の明細の数だけ出来事が重なるので、請求書と発注の組を EXISTS で 1 つにする
    def self.sql(orders)
      <<~SQL
        WITH scoped_orders AS (#{orders.select(:id, :owner_tenant_id, :created_at, :awaiting_match_at, :accepted_at, :supplier_cancelled_at).to_sql})
        SELECT orders.id, orders.owner_tenant_id, events.kind, events.occurred_at, NULL::date, orders.id
        FROM scoped_orders orders
        CROSS JOIN LATERAL (VALUES ('ordered', orders.created_at), ('part_match_pending', orders.awaiting_match_at),
          ('accepted', orders.accepted_at), ('supplier_cancelled', orders.supplier_cancelled_at)) AS events (kind, occurred_at)
        WHERE events.occurred_at IS NOT NULL
        UNION ALL
        SELECT orders.id, orders.owner_tenant_id, events.kind, events.occurred_at, NULL::date, requests.id
        FROM scoped_orders orders
        JOIN cancellation_requests requests ON requests.purchase_order_id = orders.id
        CROSS JOIN LATERAL (VALUES ('cancellation_requested', requests.created_at),
          ('cancellation_' || requests.outcome, requests.decided_at)) AS events (kind, occurred_at)
        WHERE events.occurred_at IS NOT NULL
        UNION ALL
        SELECT orders.id, orders.owner_tenant_id, 'shipped', NULL::timestamp, shipments.shipped_on, shipments.id
        FROM scoped_orders orders
        JOIN inbound_shipments shipments ON shipments.purchase_order_id = orders.id
        UNION ALL
        SELECT orders.id, orders.owner_tenant_id, 'inspected', NULL::timestamp, inspections.inspected_on, inspections.id
        FROM scoped_orders orders
        JOIN inbound_shipments shipments ON shipments.purchase_order_id = orders.id
        JOIN receipt_inspections inspections ON inspections.inbound_shipment_id = shipments.id
        UNION ALL
        SELECT orders.id, orders.owner_tenant_id, 'invoice_received', NULL::timestamp, invoices.issued_on, invoices.id
        FROM scoped_orders orders
        JOIN received_invoices invoices ON EXISTS (
          SELECT 1 FROM received_invoice_lines invoice_lines
          JOIN purchase_order_lines order_lines ON order_lines.id = invoice_lines.purchase_order_line_id
          WHERE invoice_lines.received_invoice_id = invoices.id AND order_lines.purchase_order_id = orders.id)
      SQL
    end
    private_class_method :entry, :sql
  end
end
