import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// 単体テストは lib/ の純粋関数だけが対象 (仕様 cycle-02 §7 T-37)。
// 既定の include は e2e/**/*.spec.ts も拾い、Playwright のテストを
// Vitest で走らせて落ちるので、対象を絞る
export default defineConfig({
  resolve: {
    alias: { "@": fileURLToPath(new URL(".", import.meta.url)) },
  },
  test: {
    include: ["lib/**/*.test.ts"],
    environment: "node",
  },
});
