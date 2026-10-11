class CreateInvoiceIssue < ActiveRecord::Migration[8.1]
  include TenantTable

  # 請求書の確定の採番と、確定した請求書を変えないトリガーと、発注側の受領請求書
  # （docs/architecture/data-model.md「請求（`billing`）」「購買（`purchasing`）」）。
  # received_invoices.invoice_id・supplier_tenant_id はコンテキストかテナントをまたぐ ID 参照で、外部キーを張らない
  def change
    # テナントごとに 1 行。確定するたびに DocumentNumber.next が last_number を進める
    create_tenant_table :invoice_sequences, comment: "[請求] 請求番号の採番行。テナントごとに 1 行で、最後に払い出した番号を持つ" do |t|
      t.integer :last_number, null: false, default: 0
      t.timestamps

      t.index :owner_tenant_id, unique: true
    end

    create_tenant_table :received_invoices, comment: "[購買] 受領請求書。「請求書発行」の写しで、請求書ごとに 1 行" do |t|
      t.uuid :invoice_id, null: false
      t.uuid :supplier_tenant_id, null: false
      t.string :invoice_number, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.date :issued_on, null: false
      t.bigint :subtotal, null: false
      t.bigint :tax_total, null: false
      t.bigint :total, null: false
      t.timestamps

      # 「請求書発行」の冪等キー
      t.index :invoice_id, unique: true
      t.check_constraint "total = subtotal + tax_total", name: "received_invoices_total_sum"
    end

    create_tenant_table :received_invoice_lines, comment: "[購買] 受領請求書の明細。発注明細ごとの品目名・単価・数量・税率・金額の写し" do |t|
      t.string :item_name, null: false
      t.bigint :unit_price, null: false
      t.integer :quantity, null: false
      t.integer :tax_rate_percent, null: false
      t.bigint :amount, null: false
      t.timestamps
    end
    add_tenant_reference :received_invoice_lines, :received_invoices
    # 明細は自社の発注明細を指す。発注明細は同じコンテキストの表なので、所有テナントの食い違いを複合外部キーで止める
    add_tenant_reference :received_invoice_lines, :purchase_order_lines

    reversible do |dir|
      dir.up do
        safety_assured do
          # 公開 API の CONFLICT だけでは、公開 API を通らない書き込みを止められないので、確定した請求書と、それに結んだ
          # 集計と明細の書き換えを DB で拒む。下書きの UPDATE（確定そのもの）は通す。
          # 関数は呼び出し元の search_path で別の表を引かないよう、表をスキーマで修飾して search_path を固定する
          execute <<~SQL
            CREATE FUNCTION invoices_issued_immutable() RETURNS trigger LANGUAGE plpgsql
            SET search_path = pg_catalog, pg_temp AS $$
            BEGIN
              IF OLD.issued_at IS NOT NULL THEN
                RAISE EXCEPTION '確定した請求書は変えられない（invoices %）', OLD.id;
              END IF;
              IF TG_OP = 'DELETE' THEN
                RETURN OLD;
              END IF;
              RETURN NEW;
            END
            $$;

            CREATE TRIGGER invoices_issued_immutable BEFORE UPDATE OR DELETE ON invoices
              FOR EACH ROW EXECUTE FUNCTION invoices_issued_immutable();

            -- invoice_tax_summaries と billable_items に共通。変える前の行と変えた後の行のどちらかが確定した請求書に
            -- 結んでいれば拒む。請求書の行を FOR SHARE で読むので、確定の UPDATE がコミットするまで待ち、
            -- 確定の直前に読んだ下書きの状態で明細を結んでしまうことがない
            CREATE FUNCTION invoice_children_issued_immutable() RETURNS trigger LANGUAGE plpgsql
            SET search_path = pg_catalog, pg_temp AS $$
            BEGIN
              IF TG_OP <> 'INSERT' AND OLD.invoice_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.invoices
                WHERE owner_tenant_id = OLD.owner_tenant_id AND id = OLD.invoice_id AND issued_at IS NOT NULL FOR SHARE
              ) THEN
                RAISE EXCEPTION '確定した請求書は変えられない（% %）', TG_TABLE_NAME, OLD.id;
              END IF;
              IF TG_OP <> 'DELETE' AND NEW.invoice_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.invoices
                WHERE owner_tenant_id = NEW.owner_tenant_id AND id = NEW.invoice_id AND issued_at IS NOT NULL FOR SHARE
              ) THEN
                RAISE EXCEPTION '確定した請求書は変えられない（% %）', TG_TABLE_NAME, NEW.id;
              END IF;
              IF TG_OP = 'DELETE' THEN
                RETURN OLD;
              END IF;
              RETURN NEW;
            END
            $$;

            CREATE TRIGGER invoice_tax_summaries_issued_immutable BEFORE INSERT OR UPDATE OR DELETE ON invoice_tax_summaries
              FOR EACH ROW EXECUTE FUNCTION invoice_children_issued_immutable();
            CREATE TRIGGER billable_items_issued_immutable BEFORE INSERT OR UPDATE OR DELETE ON billable_items
              FOR EACH ROW EXECUTE FUNCTION invoice_children_issued_immutable();
          SQL
        end
      end
      dir.down do
        safety_assured do
          execute <<~SQL
            DROP TRIGGER billable_items_issued_immutable ON billable_items;
            DROP TRIGGER invoice_tax_summaries_issued_immutable ON invoice_tax_summaries;
            DROP TRIGGER invoices_issued_immutable ON invoices;
            DROP FUNCTION invoice_children_issued_immutable();
            DROP FUNCTION invoices_issued_immutable();
          SQL
        end
      end
    end
  end
end
