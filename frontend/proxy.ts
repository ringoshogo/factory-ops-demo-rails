import { NextResponse, type NextRequest } from "next/server";
import securityHeaders from "./security-headers.json";

// ヘッダの値は security-headers.json にだけ置き、ここは nonce の差し込みだけを行う
const NONCE_PLACEHOLDER = "{nonce}";
const CSP_TEMPLATE = securityHeaders.headers.find((h) => h.value.includes(NONCE_PLACEHOLDER))!;

export function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");

  let csp = CSP_TEMPLATE.value.replaceAll(NONCE_PLACEHOLDER, nonce);
  if (process.env.NODE_ENV === "development") {
    // dev サーバーの HMR は eval を使う。本番の値 (JSON) は変えない
    csp = csp.replace("script-src ", "script-src 'unsafe-eval' ");
  }

  // Next は要求のヘッダの CSP から nonce を読んでスクリプトに付ける。応答のヘッダはブラウザに CSP を届ける
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(CSP_TEMPLATE.key, csp);

  const response = NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set(CSP_TEMPLATE.key, csp);
  return response;
}

export const config = {
  // 静的なファイルは Next が直接返し、nonce も要らないので通さない。取り込みのファイルは Rails へ書き換えて送るので通さない
  matcher: ["/((?!_next/static|_next/image|favicon.ico|imports/files).*)"],
};
