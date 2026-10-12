"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";

/** 取り込みが終わるまでの読み直しの間隔。取り込みは数秒から数分で終わる。 */
const INTERVAL_MS = 3000;

/**
 * 取り込みが終わるまで、数秒ごとに画面を読み直す。読み直しはサーバーコンポーネントの描き直しで、ブラウザは Rails を
 * 直接呼ばない。終わった取り込み (`finished`) では何もしない。
 */
export function ImportRefresher({ finished }: { finished: boolean }) {
  const router = useRouter();
  useEffect(() => {
    if (finished) return;
    const timer = setInterval(() => router.refresh(), INTERVAL_MS);
    return () => clearInterval(timer);
  }, [finished, router]);
  return null;
}
