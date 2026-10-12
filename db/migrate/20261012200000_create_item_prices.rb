class CreateItemPrices < ActiveRecord::Migration[8.1]
  include TenantTable

  # 販売単価の履歴と、受注明細が単価を引いた有効日（docs/architecture/data-model.md「受注（`sales`）」「RLS」、docs/adr/006）。
  # 既存の items.unit_price の値は、rake タスク sales:backfill_item_prices が写す。列は写した後のマイグレーションで消す
  def change
    # uuid の等しさを GiST の排他制約で扱うために入れる。信頼された拡張なので、スーパーユーザーでない所有ロールで入れられる
    enable_extension "btree_gist"

    # 時刻列を持たない。行を書き換えないので、記録期間の始まりが作成の時刻を兼ねる
    create_tenant_table :item_prices, comment: "[受注] 販売単価の履歴。有効期間と記録期間を持ち、行を書き換えずに改定と訂正を足す" do |t|
      t.bigint :unit_price, null: false
      t.daterange :valid_period, null: false
      t.tstzrange :recorded_period, null: false
      t.string :reason
      # 操作者。移行のタスクが写した行は空
      t.uuid :recorded_by_user_id

      t.check_constraint "unit_price >= 0", name: "item_prices_unit_price_non_negative"
      t.check_constraint "NOT isempty(valid_period)", name: "item_prices_valid_period_not_empty"
      # 記録期間は始まりを含み終わりを含まない。閉じた行の終わりと、同じ時刻に足した行の始まりが重ならずに接する
      t.check_constraint "lower_inc(recorded_period) AND NOT upper_inc(recorded_period)", name: "item_prices_recorded_period_half_open"
    end
    add_tenant_reference :item_prices, :items

    # 照合前は空で、照合で単価と一緒に埋まる。「揃って空か揃って埋まる」CHECK 制約には、移行のタスクが既存の明細を埋めた後に足す
    add_column :sales_order_lines, :priced_on, :date
    # 列を消すまでの間、新しい品目は単価をこの列に書かない
    change_column_null :items, :unit_price, true

    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<~SQL
            -- 記録期間が終わっていない行（現在の行）同士は、同じ品目で有効期間が重ならない
            ALTER TABLE item_prices ADD CONSTRAINT item_prices_current_no_overlap
              EXCLUDE USING gist (owner_tenant_id WITH =, item_id WITH =, valid_period WITH &&)
              WHERE (upper_inf(recorded_period));

            -- 行を書き換えない。許すのは、現在の行の記録期間の上限だけを、始まりより後の時刻にする UPDATE（閉じる）と、
            -- 現在の行の INSERT だけで、DELETE はすべて拒む。所有ロールの書き換えも拒む。
            -- 時刻の値そのものは確かめない。記録の時刻はアプリが 1 回の操作で 1 つ決める（docs/adr/006 決定 3）
            CREATE FUNCTION item_prices_immutable() RETURNS trigger LANGUAGE plpgsql
            SET search_path = pg_catalog, pg_temp AS $$
            BEGIN
              IF TG_OP = 'DELETE' THEN
                RAISE EXCEPTION '単価の行は消せない（item_prices %）', OLD.id;
              ELSIF TG_OP = 'INSERT' THEN
                IF NOT upper_inf(NEW.recorded_period) OR lower_inf(NEW.recorded_period) THEN
                  RAISE EXCEPTION '単価の行は、記録期間の始まりがあり終わりの無い現在の行として足す';
                END IF;
                RETURN NEW;
              END IF;
              IF NOT upper_inf(OLD.recorded_period) OR upper_inf(NEW.recorded_period) OR isempty(NEW.recorded_period)
                 OR lower(NEW.recorded_period) IS DISTINCT FROM lower(OLD.recorded_period)
                 OR (NEW.id, NEW.owner_tenant_id, NEW.item_id, NEW.unit_price, NEW.valid_period, NEW.reason, NEW.recorded_by_user_id)
                    IS DISTINCT FROM
                    (OLD.id, OLD.owner_tenant_id, OLD.item_id, OLD.unit_price, OLD.valid_period, OLD.reason, OLD.recorded_by_user_id) THEN
                RAISE EXCEPTION '単価の行は、現在の行の記録期間を閉じる以外に変えられない（item_prices %）', OLD.id;
              END IF;
              RETURN NEW;
            END
            $$;

            CREATE TRIGGER item_prices_immutable BEFORE INSERT OR UPDATE OR DELETE ON item_prices
              FOR EACH ROW EXECUTE FUNCTION item_prices_immutable();
          SQL
        end
      end
      dir.down do
        safety_assured do
          execute <<~SQL
            DROP TRIGGER item_prices_immutable ON item_prices;
            DROP FUNCTION item_prices_immutable();
          SQL
        end
      end
    end

    # 経路 1：品目が見える相手（公開品目と有効な取引関係）に、現在の行だけを見せる。今日の行に絞るのは
    # Sales::PublishedCatalog が受け持つ。品目は呼び出し元の権限で引くので、品目の RLS がそのまま効く
    add_partner_read_policy :item_prices, using: "upper_inf(recorded_period) AND EXISTS (SELECT 1 FROM items i WHERE i.id = item_id)"
  end
end
