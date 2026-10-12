"use client";

import { FieldError } from "@/components/form-errors";
import { ActionButton, FieldRow, FormDialog } from "@/components/form-dialog";
import { Input } from "@/components/ui/input";
import {
  establishPartnership,
  grantPermission,
  revokePartnership,
  withdrawPermission,
} from "@/lib/actions/supplier-master";
import type { PartnershipPermission } from "@/lib/graphql/generated";
import { PERMISSION_LABEL } from "@/lib/statuses";

/**
 * 取引関係を結ぶダイアログ。相手は発注側テナントの取引用コードで指定する。テナントのコードや名前は推測できるので
 * 受け付けない。取引用コードは、発注側の管理者が自社の情報の画面で読み、業務の外で受注側へ伝える。
 */
export function EstablishDialog() {
  return (
    <FormDialog
      label="取引関係を結ぶ"
      title="取引関係を結ぶ"
      description="発注側の管理者から伝えられた取引用コードを入れます。結んだ後に、相手に許す権限を付与します。"
      action={establishPartnership}
      submitLabel="結ぶ"
    >
      {(state) => (
        <FieldRow id="partner-code" label="取引用コード" error={<FieldError state={state} name="partnerCode" />}>
          <Input id="partner-code" name="partnerCode" required autoComplete="off" />
        </FieldRow>
      )}
    </FormDialog>
  );
}

/** 失効。失効させた関係は戻せず、相手のカタログ・発注・出荷の参照が閉じる。取引を再開するには結び直す。 */
export function RevokeDialog({ partnershipId, buyerName }: { partnershipId: string; buyerName: string }) {
  return (
    <FormDialog
      label="失効させる"
      variant="outline"
      size="sm"
      title={`${buyerName} との取引関係を失効させる`}
      description="失効させると、相手はカタログ・発注の登録・出荷の参照ができなくなります。失効は取り消せません。取引を再開するには、改めて取引関係を結びます。"
      action={revokePartnership}
      submitLabel="失効させる"
    >
      {() => <input type="hidden" name="partnershipId" value={partnershipId} />}
    </FormDialog>
  );
}

/** 権限の付与と撤回のボタン。付与していれば撤回、していなければ付与を出す。 */
export function PermissionToggle({
  partnershipId,
  permission,
  granted,
}: {
  partnershipId: string;
  permission: PartnershipPermission;
  granted: boolean;
}) {
  return (
    <ActionButton
      action={granted ? withdrawPermission : grantPermission}
      fields={{ partnershipId, permission }}
      label={`${granted ? "−" : "＋"} ${PERMISSION_LABEL[permission]}`}
      ariaLabel={`${PERMISSION_LABEL[permission]}を${granted ? "撤回" : "付与"}`}
      variant="outline"
    />
  );
}
