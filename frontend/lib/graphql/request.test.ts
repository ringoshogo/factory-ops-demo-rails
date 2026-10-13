import { parse } from "graphql";
import { RequestCookies, ResponseCookies } from "next/dist/compiled/@edge-runtime/cookies";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Rails を呼ぶ口の応答の分け方と、セッションの Cookie の写し。fetch・cookies()・redirect を差し替えて確かめる
const jar = { cookies: new ResponseCookies(new Headers()) };
vi.mock("next/headers", () => ({ cookies: async () => jar.cookies }));
vi.mock("next/navigation", () => ({
  redirect: (path: string) => {
    throw new Error(`REDIRECT ${path}`);
  },
}));

const { mutate, query, sessionHeader, forwardImportFile } = await import("./request");

const DOCUMENT = parse("query Probe { viewer { id } }") as never;
// Rails が書く形の値。`+` と `=` を URL の形で持つ
const RAILS_VALUE = "abc%2Bdef%3D%3D--sig";
const SET_COOKIE = `_factory_ops_session=${RAILS_VALUE}; path=/; expires=Wed, 14 Oct 2026 04:00:00 GMT; httponly; samesite=lax`;

const fetchMock = vi.fn();

beforeEach(() => {
  jar.cookies = new ResponseCookies(new Headers());
  // ブラウザから届いた Cookie。Next は読むときに復号するので、届いた値を RequestCookies で読んだ形で置く
  const received = new RequestCookies(new Headers({ cookie: `_factory_ops_session=${RAILS_VALUE}` }));
  jar.cookies.set("_factory_ops_session", received.get("_factory_ops_session")!.value);
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => vi.unstubAllGlobals());

const json = (body: unknown, init: ResponseInit = {}) =>
  new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" }, ...init });

describe("応答の分け方", () => {
  it("data が返れば ok", async () => {
    fetchMock.mockResolvedValue(json({ data: { viewer: { id: "u1" } } }));
    expect(await query(DOCUMENT)).toEqual({ kind: "ok", data: { viewer: { id: "u1" } } });
  });

  it("401 はセッションが切れた先 (/session/expired) へ移す", async () => {
    fetchMock.mockResolvedValue(new Response(null, { status: 401 }));
    await expect(query(DOCUMENT)).rejects.toThrow("REDIRECT /session/expired");
  });

  it("5xx・接続の失敗・時間切れ・JSON でない本文は unreachable", async () => {
    fetchMock.mockResolvedValueOnce(new Response("oops", { status: 503 }));
    expect(await query(DOCUMENT)).toEqual({ kind: "unreachable" });
    fetchMock.mockRejectedValueOnce(new TypeError("fetch failed"));
    expect(await query(DOCUMENT)).toEqual({ kind: "unreachable" });
    fetchMock.mockRejectedValueOnce(new DOMException("timeout", "TimeoutError"));
    expect(await query(DOCUMENT)).toEqual({ kind: "unreachable" });
    fetchMock.mockResolvedValueOnce(new Response("<html>", { status: 200 }));
    expect(await query(DOCUMENT)).toEqual({ kind: "unreachable" });
  });

  it("トップレベルの errors と、401 以外の 4xx は error", async () => {
    fetchMock.mockResolvedValueOnce(json({ data: null, errors: [{ message: "Forbidden", extensions: { code: "FORBIDDEN" } }] }));
    expect((await query(DOCUMENT)).kind).toBe("error");
    fetchMock.mockResolvedValueOnce(new Response(null, { status: 415 }));
    expect((await query(DOCUMENT)).kind).toBe("error");
  });

  it("Cookie が無ければ Rails を呼ばずにログインの画面へ移す", async () => {
    jar.cookies.delete("_factory_ops_session");
    await expect(query(DOCUMENT)).rejects.toThrow("REDIRECT /");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("セッションの Cookie", () => {
  it("Rails へは、Rails が書いた形の値で送る (Next が復号して返した値を URL の形に戻す)", async () => {
    fetchMock.mockResolvedValue(json({ data: { viewer: { id: "u1" } } }));
    await query(DOCUMENT);
    expect(fetchMock.mock.calls[0][1].headers.Cookie).toBe(`_factory_ops_session=${RAILS_VALUE}`);
    expect(sessionHeader("a+b==")).toBe("_factory_ops_session=a%2Bb%3D%3D");
  });

  it("書き込みは、Rails が書き直した Cookie を同じ値と属性でブラウザへ写し、読み取りは写さない", async () => {
    fetchMock.mockResolvedValue(json({ data: { viewer: { id: "u1" } } }, { headers: { "set-cookie": SET_COOKIE.replace("abc", "new") } }));
    await query(DOCUMENT);
    expect(jar.cookies.get("_factory_ops_session")!.value).toBe("abc+def==--sig");

    await mutate(DOCUMENT);
    const written = jar.cookies.get("_factory_ops_session")!;
    expect(written).toMatchObject({ httpOnly: true, sameSite: "lax", path: "/", secure: false });
    expect(written.expires).toEqual(new Date("Wed, 14 Oct 2026 04:00:00 GMT"));
    // ブラウザへ書く Set-Cookie の値は、Rails が書いた形と同じ (二重に符号化しない)
    expect(jar.cookies.toString()).toContain("_factory_ops_session=new%2Bdef%3D%3D--sig");
  });
});

describe("取り込みのファイルの送信", () => {
  it("本文と Content-Type と Origin とセッションをそのまま Rails へ送り、応答の状態と本文を返す", async () => {
    fetchMock.mockResolvedValue(json({ id: "f1" }, { status: 201, headers: { "content-type": "application/json", "set-cookie": SET_COOKIE } }));
    const body = new FormData();
    body.append("file", new Blob(["item_code,quantity\n"]), "stocks.csv");
    const request = new Request("http://localhost:3001/imports/files", { method: "POST", body, headers: { origin: "http://localhost:3001" } });

    const res = await forwardImportFile(request);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toMatch(/\/imports\/files$/);
    expect(init.headers.Origin).toBe("http://localhost:3001");
    expect(init.headers.Cookie).toBe(`_factory_ops_session=${RAILS_VALUE}`);
    expect(init.headers["Content-Type"]).toMatch(/^multipart\/form-data; boundary=/);
    expect(new TextDecoder().decode(init.body)).toContain("item_code,quantity");
    expect(res.status).toBe(201);
    expect(await res.json()).toEqual({ id: "f1" });
  });

  it("Rails に届かなければ 502", async () => {
    fetchMock.mockRejectedValue(new TypeError("fetch failed"));
    const request = new Request("http://localhost:3001/imports/files", { method: "POST", body: "x" });
    expect((await forwardImportFile(request)).status).toBe(502);
  });
});

describe("readSessionCookie", () => {
  it("名前・値・期限・Secure を読み、ほかの名前の Cookie は読まない", async () => {
    const { readSessionCookie } = await import("@/lib/session");
    const res = new Response(null, { headers: [["set-cookie", "other=1; path=/"], ["set-cookie", `${SET_COOKIE}; secure`]] });
    expect(readSessionCookie(res)).toEqual({ value: RAILS_VALUE, expires: new Date("Wed, 14 Oct 2026 04:00:00 GMT"), secure: true });
    expect(readSessionCookie(new Response(null, { headers: { "set-cookie": "other=1" } }))).toBeNull();
  });
});
