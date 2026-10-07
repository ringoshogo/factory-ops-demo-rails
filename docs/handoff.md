# 引き継ぎ：作業の現在地と次の一手

新しいセッションで作業を再開する人（Claude を含む）が最初に読む文書。プロジェクトの目的、決まったこと、決まっていないこと、次にやることを示す。

## 目的

このリポジトリは、作者が Rails のアーキテクトとして設計判断できることを示すポートフォリオである。見せたいのは動く機能の多さではない。設計判断（`architecture/decisions.md`）が、コードのどこで、どの仕組みで守られているかを読み手が辿れることである。

実装の優先順位はこの目的で決める。見せどころは次の 3 つ。

- **相互アクセス型マルチテナントの境界**：相手テナントのデータを読める経路が限られていること、取引関係の失効で閉じること、相手の名義で書けないこと
- **コンテキスト間の疎結合**：packwerk が CI で強制していること、テナントをまたぐ連結がイベントだけで行われること
- **GraphQL で相手側のデータへたどれないこと**

一方、フロントエンドは見せどころではない。姉妹プロジェクト `factory-ops-demo` の Next.js を流用し、データ取得層だけを GraphQL に書き換える。

## 読む順

1. `../README.md`：構成の要約
2. `architecture/context-map.md`：業務の流れと 6 つのコンテキスト、つなぎ方、品番照合・取消・検収と請求の流れ、取引関係の失効、許可する依存の向き、テナントの所有
3. `architecture/data-model.md`：テナントの持ち方、状態の導出、各コンテキストのテーブル、取消と出荷の競合の止め方、イベントの冪等キー、RLS
4. `architecture/graphql-schema.md`：GraphQL の型を視点ごとに分ける形、相手側へたどれないことの保証、認可の基底クラス、クエリと mutation が呼ぶ公開 API
5. `architecture/decisions.md`：設計判断の一般原則。各論点の既定の推奨と裏返る条件
6. `adr/`：本デモで下した個別の判断
7. `implementation-plan.md`：実装の順番。マイルストーンの一覧と、各マイルストーンの完了条件。実装を始める人は、着手するマイルストーンの節と、そこが挙げる設計文書の節を読む

`decisions.md` は一般論で、完全分離型のマルチテナントも扱う。本デモに当てはめた結果は `context-map.md`・`data-model.md`・`graphql-schema.md`・`adr/` にある。両者が食い違う場合は `adr/` が優先する。

## 決まったこと

| 項目 | 決定 | 根拠 |
|---|---|---|
| 題材 | factory-ops-demo と同じく、架空の機械部品メーカー「青嵐精機工業」の受発注・在庫管理 | ユーザー判断 |
| マルチテナント | 相互アクセス型。発注側と受注側が同じシステムを使い、発注が相手の受注に連結する | ユーザー判断、`context-map.md` |
| コンテキスト | 取引関係・購買・受注・在庫・出荷・請求の 6 つ＋イベント置き場 `contracts` | `context-map.md` |
| 発注側からの取消 | 可能。受注側の承認が要る。審査の間は出荷を止める | ユーザー判断、`context-map.md`「取消の流れ」 |
| 品番 | 発注側は自社品番で発注する。受注側の腐敗防止層が対応表で読み替える | ユーザー判断、`context-map.md`「発注の連結と品番の照合」 |
| 検収と請求 | 検収の結果を「検収完了」で受注側へ返す。受注側が検収数量 × 受注単価で取引先ごとに月次で締めて請求書を発行し、発注側は「請求書発行」で届いた写しを閲覧する。入金消込は範囲外 | ユーザー判断、`context-map.md`「検収と請求の流れ」 |
| 取引関係の失効 | 読む 3 経路と新しい発注は閉じる。「発注登録」を出し終えた取引は請求まで進む | ユーザー判断、`context-map.md`「取引関係の失効」 |
| 構成 | Rails（API モード）＋PostgreSQL＋GraphQL。フロントは factory-ops-demo の Next.js を流用 | ユーザー判断 |
| スキーマ管理 | Rails マイグレーション＋`structure.sql`。ridgepole は使わない | `adr/001` |
| 主キー | UUIDv7 を DB の `uuidv7()` で作る。PostgreSQL 18 以降を使う | `adr/003` |
| データモデル | 全テーブルに `owner_tenant_id`、親子は複合外部キー、状態は時刻列から導出、引当は在庫だけが持つ。RLS の `WITH CHECK` は全表で所有テナントに限り、読む 3 経路にだけ SELECT のポリシーを足す | `architecture/data-model.md` |
| 境界の強制 | 初日から `packs/` 構成。packwerk の依存チェックとプライバシーチェックを CI で強制する | ユーザー判断、`adr/002` |
| イベントの配送 | Solid Queue を業務 DB と同じ接続に置き、イベントのジョブは業務のトランザクションの中で登録する（`EventJob` は `enqueue_after_transaction_commit = false`、それ以外の `ApplicationJob` は `true`）。outbox は置かない。キューの接続が同じであることをテストで固定する | `adr/005` |
| テスト | RSpec＋FactoryBot。設計文書がガードテストを `spec/` のパスで定めているため | `implementation-plan.md`「環境」 |
| 基盤パッケージ | `packs/platform` を足し、`ApplicationRecord`・`ApplicationJob`・`Current`・`Tenancy` を置く。基底クラスをルートパッケージに置くと、パッケージからルートへの依存が循環になるため | `implementation-plan.md` M2 |
| GraphQL | graphql-ruby と Action Policy。1 つのスキーマで `buyer`・`supplier` の入口を分け、型に視点を宣言させて到達可能性をテストで固定する。汎用の `node` は置かない。基底の型・リゾルバ・mutation は宣言が無ければ拒否する | `architecture/graphql-schema.md`、`adr/004` |

## 決まっていないこと

- **GitHub リポジトリの公開範囲（public / private）**：いまは private で作ってある

## 未確認の事項

どれも、確かめるマイルストーンが決まっている。確かめたら、該当する ADR の未確認の事項を結果で置き換える。

- packs-rails が Rails 8 系に対応しているか（`adr/002`）。M2 で確かめる。動かなければ、自動読み込みの設定を手で書く
- RLS を付けない Solid Queue の表を、アプリと同じ DB ロールのワーカーが読めること（`adr/005`）。M7 で確かめる

`adr/005` の残り 2 つは、`implementation-plan.md` M7 で決めた。`EventJob` は `packs/contracts` の `Contracts::EventJob` にし、テストでも `:test` アダプタに差し替えず `:solid_queue` のまま使う。M7 で ADR に反映する。

## 次にやること

順に進める。各段階で決めたことは、`adr/`・`context-map.md`・`data-model.md`・`graphql-schema.md` のいずれかに残す。

1. **`implementation-plan.md` の M1 から順に実装する**：1 つのマイルストーンの完了条件をすべて通してから、次へ進む。
2. **CI の確認**：M1 で作った CI が、M1 の commit を最初に push したときに通ることを確かめる。

## リポジトリの状態

- **このリポジトリ**：ブランチ `main`。リモートは GitHub の `ringo-shg/factory-ops-demo-rails`（private）。
- **実装**：M1 まで終えた。`implementation-plan.md` のマイルストーンを終えるたびに、ここへ書く。
- **親のモノレポ（`shogo-project`）**：`.gitignore` に `/factory-ops-demo-rails/` を追加し、README の「別リポジトリで管理しているもの」の表に行を足した。どちらも未 commit である。

## 持ち込まなかったもの

`decisions.md` は、作者の勤務先で行った 3 者の討論（Rails Way 派・構造化派・Codex）の結論である。討論の原文と、根拠として添えていた勤務先コードの観察は、社内のコードを含むため持ち込んでいない。勤務先のコード・社名・顧客名は、このリポジトリに書かない。
