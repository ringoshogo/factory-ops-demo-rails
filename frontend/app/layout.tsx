import type { Metadata } from "next";
import { IBM_Plex_Sans } from "next/font/google";
import "./globals.css";
import { themeClass } from "@/lib/theme";
import { readTheme } from "@/lib/theme-cookie";

// 英数字だけを自前で配る (CSP の font-src 'self')。和文は OS のフォントに任せる。和文の Web フォントは
// unicode-range ごとに数十のファイルに分かれ、最初の表示の要求が増える。太さは 400・500・600 の 3 つだけを使う
const plexSans = IBM_Plex_Sans({
  variable: "--font-plex-sans",
  weight: ["400", "500", "600"],
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: "受発注・在庫・請求デモ",
  description:
    "架空の機械部品メーカーと取引先の組立メーカーを題材にした、マルチテナントの受発注・在庫・請求のデモ。データはすべて架空です。",
};

export default async function RootLayout({ children }: LayoutProps<"/">) {
  // テーマはサーバーが描く時点で決める。インラインのスクリプトでクラスを付け直さないので、選んだテーマと逆のテーマが
  // 一瞬見えることがない
  const theme = await readTheme();

  return (
    <html lang="ja" className={`${plexSans.variable} ${themeClass(theme)} h-full antialiased`}>
      <body className="flex min-h-full flex-col">
        {/* 画面の枠はルートグループが描く。ログインの画面は (entry)、それ以外は (app) */}
        {children}
      </body>
    </html>
  );
}
