import { forwardImportFile } from "@/lib/graphql/request";

// 取り込みのファイルの受け口。ブラウザは同じオリジンのここへ送り、Rails を直接呼ばない。Rails の URL は実行の時の
// RAILS_URL で決める (next.config.mjs の rewrites はビルドの時の値で固まるので使わない)
export async function POST(request: Request) {
  return forwardImportFile(request);
}
