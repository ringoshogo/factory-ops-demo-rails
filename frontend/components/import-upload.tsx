"use client";

import { useId, useState, useTransition } from "react";
import { ErrorNotice } from "@/components/error-notice";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { startImport } from "@/lib/actions/imports";
import { EXPIRED_PATH } from "@/lib/session";

// lib/graphql/user-errors.ts の同じ文言は next/cache を読み込むので、クライアント部品からは読み込めない
const UNREACHABLE_MESSAGE = "API に接続できませんでした。時間をおいてもう一度お試しください。";

/** 応答の状態ごとの文言。413 と 400 と 403 は Rails の ImportFilesController が返す。 */
const UPLOAD_ERRORS: Record<number, string> = {
  400: "ファイルを選んでください。",
  403: "この画面のオリジンからは送れません。画面を開き直してください。",
  413: "ファイルが大きすぎます。",
};

/**
 * 取り込みの開始。ファイルはブラウザから同じオリジンの /imports/files (app/imports/files/route.ts が Rails へ
 * そのまま送る) へ multipart/form-data で送り、返ったファイルの ID で取り込みを始める server action を呼ぶ。
 * server action に渡さないので、server action の本文の上限に掛からない。Rails は Origin ヘッダを許可した
 * フロントエンドのオリジンと比べて、他サイトからの送信を拒む。セッションが切れていれば (401)、ほかの画面と同じく
 * Cookie を消してログインの画面へ移す。
 *
 * 種類 ITEMS (品目と単価) は admin に限る操作なので、admin にだけ選択肢を出す。STOCKS (在庫) は役割を問わない。
 */
export function ImportUpload({ admin }: { admin: boolean }) {
  const id = useId();
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit(form: FormData) {
    setMessage(null);
    const kind = String(form.get("kind") ?? "");
    const file = form.get("file");
    if (!(file instanceof File) || file.size === 0) {
      setMessage(UPLOAD_ERRORS[400]);
      return;
    }
    startTransition(async () => {
      const body = new FormData();
      body.append("file", file);
      let res: Response;
      try {
        res = await fetch("/imports/files", { method: "POST", body });
      } catch {
        setMessage(UNREACHABLE_MESSAGE);
        return;
      }
      if (res.status === 401) {
        window.location.assign(EXPIRED_PATH);
        return;
      }
      if (!res.ok) {
        setMessage(UPLOAD_ERRORS[res.status] ?? UNREACHABLE_MESSAGE);
        return;
      }
      const stored = (await res.json()) as { id?: string };
      if (!stored.id) {
        setMessage(UNREACHABLE_MESSAGE);
        return;
      }
      // 成功すると server action が進み具合の画面へ移すので、戻るのは失敗のときだけ
      const state = await startImport(stored.id, kind);
      if (state.status === "error") {
        setMessage(state.message ?? Object.values(state.fieldErrors ?? {}).join(" "));
      }
    });
  }

  return (
    <form action={submit} className="space-y-3" data-testid="import-form">
      {message && <ErrorNotice data-testid="form-error">{message}</ErrorNotice>}
      <div className="flex flex-wrap items-end gap-3">
        <div className="space-y-1.5">
          <Label htmlFor={`${id}-kind`}>種類</Label>
          <NativeSelect id={`${id}-kind`} name="kind" defaultValue="STOCKS">
            <option value="STOCKS">在庫</option>
            {admin && <option value="ITEMS">品目と単価</option>}
          </NativeSelect>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor={`${id}-file`}>CSV ファイル</Label>
          <Input id={`${id}-file`} name="file" type="file" accept=".csv,text/csv" required className="w-80" />
        </div>
        <Button type="submit" disabled={pending}>
          取り込む
        </Button>
      </div>
    </form>
  );
}
