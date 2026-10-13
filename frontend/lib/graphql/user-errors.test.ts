import { beforeEach, describe, expect, it, vi } from "vitest";

// mutation の結果をフォームの結果に分ける規則。redirect と revalidatePath を差し替えて確かめる
const revalidatePath = vi.fn();
vi.mock("next/cache", () => ({ revalidatePath: (path: string) => revalidatePath(path) }));
vi.mock("next/navigation", () => ({
  redirect: (path: string) => {
    throw new Error(`REDIRECT ${path}`);
  },
}));

const { MISSING_PATH, NOT_PERMITTED_MESSAGE, UNREACHABLE_MESSAGE, settle } = await import("./user-errors");

type Data = { op: { errors: { code: string; message: string; path: string[] | null }[] } };
const ok = (errors: Data["op"]["errors"]) => ({ kind: "ok" as const, data: { op: { errors } } });
const run = (result: Parameters<typeof settle<Data>>[0]) => settle<Data>(result, (d) => d.op, ["/a", "/b"]);

beforeEach(() => revalidatePath.mockReset());

describe("settle", () => {
  it("ユーザーエラーが無ければ ok にして、画面を読み直す", () => {
    expect(run(ok([]))).toEqual({ status: "ok" });
    expect(revalidatePath.mock.calls).toEqual([["/a"], ["/b"]]);
  });

  it("届かない・トップレベルのエラーは、フォームの上の文言にする", () => {
    expect(run({ kind: "unreachable" })).toEqual({ status: "error", message: UNREACHABLE_MESSAGE });
    expect(run({ kind: "error", message: "処理できませんでした" })).toEqual({ status: "error", message: "処理できませんでした" });
  });

  it("NOT_FOUND は見つからない画面へ移す", () => {
    expect(() => run(ok([{ code: "NOT_FOUND", message: "x", path: ["id"] }]))).toThrow(`REDIRECT ${MISSING_PATH}`);
  });

  it("NOT_PERMITTED は API の文言ではなく 1 つの文言にする", () => {
    expect(run(ok([{ code: "NOT_PERMITTED", message: "Partnership is revoked", path: null }]))).toEqual({
      status: "error",
      message: NOT_PERMITTED_MESSAGE,
    });
  });

  it("CONFLICT は読み直してから、API の文言に読み直したことを足して出す", () => {
    const state = run(ok([{ code: "CONFLICT", message: "Sales order is cancelled", path: null }]));
    expect(state).toEqual({ status: "error", message: "Sales order is cancelled（最新の状態を読み直しました）" });
    expect(revalidatePath).toHaveBeenCalledTimes(2);
  });

  it("INVALID_INPUT は path を . でつないだ鍵で入力欄に、path が無ければフォームの上に出す", () => {
    const state = run(
      ok([
        { code: "INVALID_INPUT", message: "must be positive", path: ["lines", "1", "quantity"] },
        { code: "INVALID_INPUT", message: "whole input", path: null },
      ]),
    );
    expect(state).toEqual({ status: "error", message: "whole input", fieldErrors: { "lines.1.quantity": "must be positive" } });
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});
