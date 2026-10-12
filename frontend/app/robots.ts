import type { MetadataRoute } from "next";

/**
 * クローラへの指示。ログインの画面だけを見せ、業務の画面は検索の結果に出さない。業務の画面はログインしないと
 * 開けず、ログインの画面へ移るだけだからである。
 */
export default function robots(): MetadataRoute.Robots {
  return { rules: [{ userAgent: "*", allow: "/$", disallow: ["/supplier", "/buyer", "/settings", "/audit-logs"] }] };
}
