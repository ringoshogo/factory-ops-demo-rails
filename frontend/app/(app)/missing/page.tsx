import { notFound } from "next/navigation";

// mutation が NOT_FOUND を返したときの移り先 (lib/graphql/user-errors.ts)。ID で引く入口の null と同じ見つからない画面を出す
export default function Missing() {
  notFound();
}
