import { NotFoundMessage } from "@/components/not-found-message";

// 画面群の中で見つからない (存在しないか、他社の伝票)。(app) のレイアウトがサイドバーを描くので、ここは本文だけ
export default function AppNotFound() {
  return <NotFoundMessage href="/supplier/dashboard" label="ダッシュボードへ戻る" />;
}
