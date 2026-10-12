import type { cookies } from "next/headers";
import { SESSION_COOKIE } from "@/lib/config";

type CookieJar = Awaited<ReturnType<typeof cookies>>;

/** Rails が 401 を返したときに移る先。セッションの Cookie を消してからログインの画面へ移す (app/session/expired/route.ts)。 */
export const EXPIRED_PATH = "/session/expired";

export type SessionCookie = {
  value: string;
  expires?: Date;
  secure: boolean;
};

/**
 * Rails の応答の Set-Cookie から、セッションの Cookie を読む。無ければ null。
 * 名前・値・期限・Secure だけを読み、HttpOnly・SameSite・Path は Rails の設定 (config/application.rb) と同じ値を
 * 写す側 (`writeSessionCookie`) が書く。Rails の設定と違う属性で書くと、ブラウザが同じ名前の Cookie を 2 つ持ちうる。
 */
export function readSessionCookie(res: Response): SessionCookie | null {
  for (const header of res.headers.getSetCookie()) {
    const [pair, ...attributes] = header.split(";").map((part) => part.trim());
    const eq = pair.indexOf("=");
    if (eq < 0 || pair.slice(0, eq) !== SESSION_COOKIE) continue;

    const cookie: SessionCookie = { value: pair.slice(eq + 1), secure: false };
    for (const attribute of attributes) {
      const [name, ...rest] = attribute.split("=");
      const key = name.trim().toLowerCase();
      if (key === "expires") cookie.expires = new Date(rest.join("="));
      if (key === "secure") cookie.secure = true;
    }
    return cookie;
  }
  return null;
}

/** セッションの Cookie を、フロントエンドのオリジンの Cookie としてブラウザへ書く。server action と route handler だけが呼べる。 */
export function writeSessionCookie(jar: CookieJar, cookie: SessionCookie): void {
  jar.set(SESSION_COOKIE, cookie.value, {
    httpOnly: true,
    sameSite: "lax",
    secure: cookie.secure,
    path: "/",
    expires: cookie.expires,
  });
}

/** 応答にセッションの Cookie があれば写す。Rails は応答のたびに期限を延ばした Cookie を書き直す。 */
export function copySessionCookie(res: Response, jar: CookieJar): void {
  const cookie = readSessionCookie(res);
  if (cookie) writeSessionCookie(jar, cookie);
}
