/**
 * フォームの実行結果。`useActionState` に載せるので、成功も失敗も同じ形で返す (例外にすると、どの入力で失敗したかを
 * 画面に戻せない)。"use server" のファイルは非同期関数しか export できないので、型と定数はここに置く。
 *
 * - `message`: フォームの上に出す文言
 * - `fieldErrors`: 入力欄の下に出す文言。鍵は UserError の `path` を `.` でつないだもの (`lines.1.quantity`)
 */
export type FormState = {
  status: "idle" | "ok" | "error";
  message?: string;
  fieldErrors?: Record<string, string>;
};

export const IDLE: FormState = { status: "idle" };
