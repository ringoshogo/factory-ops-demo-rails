# syntax=docker/dockerfile:1
# check=error=true

# 公開の配置の画面のイメージ（deploy/frontend.yaml）。ログインの画面が frontend/ の外の db/seeds/demo_accounts.json を読むので、
# リポジトリの根を文脈にして組み立てる。文脈に入れるものは frontend/Dockerfile.dockerignore が決める。
#   docker buildx build --platform linux/arm64 -f frontend/Dockerfile .

# CI の frontend と e2e のジョブ（actions/setup-node の 22）と同じ系にし、小版まで固定する
ARG NODE_VERSION=22.23.3
FROM docker.io/library/node:${NODE_VERSION}-slim AS build

WORKDIR /app

COPY frontend/package.json frontend/package-lock.json frontend/
RUN cd frontend && npm ci

COPY db/seeds/demo_accounts.json db/seeds/
COPY frontend/ frontend/

# next.config.mjs は NEXT_OUTPUT=standalone のときだけ、node_modules を持たないサーバーを .next/standalone に組み立てる。
# ビルドの根（outputFileTracingRoot）をリポジトリの根にしているので、サーバーは standalone の下の frontend/server.js になる
ENV NEXT_OUTPUT=standalone \
    NEXT_TELEMETRY_DISABLED=1
RUN cd frontend && npm run build


FROM docker.io/library/node:${NODE_VERSION}-slim

WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000

# 静的なファイルは standalone に入らないので、サーバーの隣に写す
COPY --chown=node:node --from=build /app/frontend/.next/standalone ./
COPY --chown=node:node --from=build /app/frontend/.next/static ./frontend/.next/static

# イメージに入っている uid 1000 の利用者で動かす。マニフェストの runAsNonRoot が uid を数で確かめる
USER 1000:1000
EXPOSE 3000
CMD ["node", "frontend/server.js"]
