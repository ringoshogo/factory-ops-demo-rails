class AddTableComments < ActiveRecord::Migration[8.1]
  # それまでに作った全表に、コンテキストの接頭辞付きの説明を付ける（docs/architecture/data-model.md「全テーブルに共通の規則」）。
  # これより後に作る表は、作るときに comment: で説明を渡す（lib/tenant_table.rb）
  COMMENTS = {
    # 取引関係
    tenants: "[取引関係] テナント。名前と、取引関係の相手の指定に使う取引用コードを持つ",
    users: "[取引関係] テナントのユーザー。ログインの資格情報とセッションの世代を持つ",
    partnerships: "[取引関係] 受注側が発注側と結ぶ取引関係。失効した関係も行として残す",
    partnership_grants: "[取引関係] 取引関係ごとの権限付与（view_catalog・place_orders・view_shipments）",
    # 購買
    purchase_orders: "[購買] 発注の見出し。状況は時刻列と入荷・検収から導出する",
    purchase_order_lines: "[購買] 発注明細。自社品番と数量、受注確定で写す品目名・単価を持つ",
    purchase_order_sequences: "[購買] 発注の伝票番号の採番行。テナントごとに最後に払い出した番号を持つ",
    inbound_shipments: "[購買] 入荷。受注側の「出荷計上」の写しで、出荷実績 1 件に 1 行",
    inbound_shipment_lines: "[購買] 入荷の明細。発注明細ごとの出荷数量を持つ",
    # 受注
    items: "[受注] 品目カタログ。公開した品目は、取引関係のある発注側から見える",
    customer_part_mappings: "[受注] 得意先品番の対応表。取引先の品番を自社の品目に照合する",
    sales_orders: "[受注] 発注から連結した受注の見出し。状況は時刻列から導出する",
    sales_order_lines: "[受注] 受注明細。照合までは品目が空で、照合で品目名・単価・税率を写す",
    sales_order_sequences: "[受注] 受注の伝票番号の採番行。テナントごとに最後に払い出した番号を持つ",
    # 在庫
    stocks: "[在庫] 品目ごとの在庫。手持ち・引当済み・安全在庫の数量を持つ",
    allocations: "[在庫] 引当。受注明細ごとに 1 行で、引き当てた数量と状態を持つ",
    stock_movements: "[在庫] 在庫移動履歴。在庫を変えるたびに追記し、書き換えない",
    # 出荷
    shipment_requests: "[出荷] 出荷依頼。受注の「出荷可能」の写しで、受注ごとに 1 件",
    shipment_request_lines: "[出荷] 出荷依頼の明細。受注明細ごとの品目と数量の写し",
    shipping_instructions: "[出荷] 出荷指示。有効な指示は出荷依頼ごとに 1 件",
    shipments: "[出荷] 出荷実績。出荷依頼を全量で計上し、発注側は自社の発注に連結した分を読む",
    shipment_lines: "[出荷] 出荷実績の明細。出荷依頼の明細ごとに 1 行",
    # 基盤（Rails が管理する表）
    schema_migrations: "[基盤] 流したマイグレーションの版。Rails が管理する",
    ar_internal_metadata: "[基盤] DB の環境名などの記録。Rails が管理する",
    # キュー（Solid Queue）
    solid_queue_jobs: "[キュー] Solid Queue に登録したジョブ。イベントもジョブとして登録する",
    solid_queue_ready_executions: "[キュー] すぐに実行できるジョブの待ち行列",
    solid_queue_scheduled_executions: "[キュー] 実行の時刻を待つジョブ",
    solid_queue_claimed_executions: "[キュー] ワーカーが取り出して実行中のジョブ",
    solid_queue_blocked_executions: "[キュー] 同時実行の上限で待たされているジョブ",
    solid_queue_failed_executions: "[キュー] 失敗したジョブと、その例外",
    solid_queue_pauses: "[キュー] 一時停止中のキュー",
    solid_queue_processes: "[キュー] 動いているワーカーなどのプロセスと、最後の生存通知",
    solid_queue_recurring_tasks: "[キュー] 定期実行するタスクの定義",
    solid_queue_recurring_executions: "[キュー] 定期実行のタスクから登録したジョブの記録",
    solid_queue_semaphores: "[キュー] 同時実行の上限を数えるセマフォ",
    solid_queue_batches: "[キュー] ジョブのバッチと、その進み具合",
    solid_queue_batch_executions: "[キュー] バッチに属するジョブと、そのバッチの対応"
  }.freeze

  def change
    COMMENTS.each do |table, comment|
      change_table_comment table, from: nil, to: comment
    end
  end
end
