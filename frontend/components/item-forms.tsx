"use client";

import { FieldError } from "@/components/form-errors";
import { ActionButton, FieldRow, FormDialog } from "@/components/form-dialog";
import { Input } from "@/components/ui/input";
import { saveItem, setItemPublished } from "@/lib/actions/supplier-master";

export type ItemFormValues = { code: string; name: string; unit: string; unitPrice: string; taxRatePercent: number };

/**
 * 品目の登録と更新のダイアログ。saveItem はコードで品目を引き、あれば書き換え、無ければ作る。既存の品目の単価は
 * この操作では変えられない (改定は予約、誤りは訂正で、品目の詳細で行う) ので、更新ではコードと単価を読むだけにする。
 */
export function ItemDialog({ item }: { item?: ItemFormValues }) {
  const editing = item !== undefined;
  return (
    <FormDialog
      label={editing ? "編集" : "品目を登録"}
      variant={editing ? "outline" : "default"}
      size={editing ? "sm" : "default"}
      title={editing ? `品目の編集（${item.code}）` : "品目の登録"}
      description={editing ? "単価は品目の詳細で、改定の予約か訂正で変えます。" : undefined}
      action={saveItem}
      submitLabel="保存"
    >
      {(state) => (
        <>
          <FieldRow id="item-code" label="品目コード" error={<FieldError state={state} name="code" />}>
            <Input id="item-code" name="code" required defaultValue={item?.code} readOnly={editing} />
          </FieldRow>
          <FieldRow id="item-name" label="品目名" error={<FieldError state={state} name="name" />}>
            <Input id="item-name" name="name" required defaultValue={item?.name} />
          </FieldRow>
          <FieldRow id="item-unit" label="単位" error={<FieldError state={state} name="unit" />}>
            <Input id="item-unit" name="unit" required defaultValue={item?.unit} placeholder="個・本・箱など" />
          </FieldRow>
          <FieldRow id="item-unit-price" label="単価（円・税抜き）" error={<FieldError state={state} name="unitPrice" />}>
            <Input
              id="item-unit-price"
              name="unitPrice"
              inputMode="numeric"
              required
              defaultValue={item?.unitPrice}
              readOnly={editing}
            />
          </FieldRow>
          <FieldRow id="item-tax" label="税率（%）" error={<FieldError state={state} name="taxRatePercent" />}>
            <Input id="item-tax" name="taxRatePercent" inputMode="numeric" required defaultValue={item?.taxRatePercent ?? 10} />
          </FieldRow>
        </>
      )}
    </FormDialog>
  );
}

/** カタログへの公開と取り下げ。 */
export function PublishButton({ itemId, published }: { itemId: string; published: boolean }) {
  return (
    <ActionButton
      action={setItemPublished}
      fields={{ itemId, published: String(!published) }}
      label={published ? "公開をやめる" : "公開する"}
      variant="ghost"
    />
  );
}
