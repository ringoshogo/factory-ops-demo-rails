import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { SESSION_COOKIE } from "@/lib/config";

// Rails がセッションを拒んだ (401) ときに request.ts が移す先。サーバーコンポーネントは Cookie を消せないので、
// ここで消してからログインの画面へ移す。他サイトから開かれても、消えるのはこのブラウザの Cookie だけで、
// Rails のセッションの世代は進まない
export async function GET() {
  (await cookies()).delete(SESSION_COOKIE);
  redirect("/?expired=1");
}
