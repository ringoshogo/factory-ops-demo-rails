# 001. スキーマ管理に ridgepole を採用せず、Rails マイグレーションと structure.sql を使う

## ステータス

提案。新規 Rails アプリの立ち上げ時に CTO が承認する。

この決定は次の 2 つの判断を前提にする。どちらかが覆った場合は、この ADR を見直す。
- DB に PostgreSQL を採用する（`../architecture/decisions.md` 8 章）
- テナント分離を DB の機能でも強制する（同 2 章）

## コンテキスト

### 決めること

スキーマを定義・変更・保存する方式を決める。候補は 4 つある。
- Rails 標準のマイグレーション＋`schema.rb`
- Rails 標準のマイグレーション＋`structure.sql`
- ridgepole（宣言的な Schemafile との差分を適用するツール）
- Rails の外にある SQL マイグレーションツール

### スキーマ管理に求めること

このアプリはマルチテナントで、テナント間の漏洩を DB でも止める設計にしている。そのため、スキーマ管理には次の 4 つが求められる。

1. **テナント強制に使う DB 機能を定義できること。** 必要な機能は次のとおり。
   - テナント列の NOT NULL と外部キー
   - 親子のテナント一致を保証する複合外部キー（`(parent_id, owner_tenant_id)` が親の `(id, owner_tenant_id)` を参照する）
   - CHECK 制約
   - PostgreSQL RLS のポリシー（`ENABLE`／`FORCE`、`USING`／`WITH CHECK`）
2. **その定義が 1 か所にあり、テスト DB に同じものが再現されること。** テスト DB にポリシーが無ければ、テストは RLS 抜きで通ってしまい、2 枚目の防壁が検証されない。
3. **ロックを長く取る変更などの危険なスキーマ変更を、CI で止められること。**
4. **データの移行（既存行へのテナント ID の補完など）を、スキーマ変更と分けて安全に実行できること。**

### 各方式で表現できること

| 必要なもの | マイグレーション＋`schema.rb` | マイグレーション＋`structure.sql` | ridgepole |
|---|---|---|---|
| NOT NULL・単一列の外部キー・CHECK 制約 | 表現できる | 表現できる | 表現できる |
| 複合外部キー | ダンプで失われる | `execute` で作成し、pg_dump がそのまま保存する | 記載なし |
| RLS のポリシー・トリガー・関数 | ダンプで失われる | pg_dump がそのまま保存する | 記載なし |
| テスト DB への再現 | 失われたものは再現されない | ダンプから完全に再現される | Schemafile に書けるものだけ再現される |
| 危険な変更の CI 検出（strong_migrations） | 使える | 使える | 対象外 |
| データの移行 | マイグレーションか、別のタスク | 同左 | 扱わない |

> Rails ガイドは「Active Record は単一列の外部キーしかサポートしない。複合外部キーには `execute` と `structure.sql` が必要」とし、`schema.rb` はトリガー・ストアドプロシージャなどを表現できないと明記している（https://guides.rubyonrails.org/active_record_migrations.html ）。ridgepole の README（v3.2.0、Rails 8.1 対応）に記載がある制約は CHECK 制約と外部キーまでで、複合外部キー・RLS・トリガーには触れていない（https://github.com/ridgepole/ridgepole ）。

## 決定

スキーマは Rails 標準のマイグレーションで管理し、保存形式を `structure.sql` にする。各項目は、立ち上げ時の CTO または初期メンバーが初日に設定する。

1. `config.active_record.schema_format = :sql` を設定し、スキーマを `db/structure.sql` に保存する。
2. RLS のポリシー・複合外部キー・トリガーなど DSL で書けないものは、マイグレーション内の `execute` で書く。そのマイグレーションには必ず `down` を書き、巻き戻せるようにする。
3. strong_migrations を導入し、危険なスキーマ変更を CI で止める。
4. データの移行はマイグレーションに入れず、maintenance_tasks などの別のタスクで実行する。
5. テナント強制の定義が欠けていないことを、テストで確かめる。
   - テナント表ごとに、テスト DB に RLS ポリシーと複合外部キーが存在すること（`pg_policies`・`pg_constraint` を引いて確かめる）
   - テスト DB への接続にはスーパーユーザーではないロールを使う（PostgreSQL のスーパーユーザーは `FORCE` を付けても RLS を迂回するため）
6. 開発環境と CI で、pg_dump（PostgreSQL クライアント）のバージョンを揃える。揃えないと `structure.sql` に本質的でない差分が出る。

## 結果

### 得られるもの

- **定義が 1 か所に集まる。** テナント強制の DB 定義がすべて、マイグレーションとその結果の `structure.sql` に揃う。
- **テスト DB が本番と同じ防壁を持つ。** RLS を含むテストが、本番と同じ条件で走る。
- **危険な変更を CI で検出できる。** strong_migrations が使える。
- **変更の履歴を巻き戻せる。** マイグレーションの `down` で、変更を 1 つずつ戻せる。

### 引き受けるコスト

- **現在のスキーマが読みにくい。** 全体を見るには `structure.sql` を読むことになり、ridgepole の Schemafile より読みにくい。
- **マイグレーションファイルが積み上がる。** 定期的にまとめ直す（squash）運用が要る。
- **PostgreSQL への依存が深まる。** `execute` の SQL は PostgreSQL 固有になる。PostgreSQL を選んだ時点でこの依存は引き受けている。
- **ridgepole に慣れたメンバーには学習コストがかかる。** 国内の Rails 現場では MySQL＋ridgepole の構成も多く、その経験者は書き方を切り替えることになる。

### 見直す条件

- **DB に MySQL を採用した場合。** RLS が無いので、ridgepole で表現できない要求は複合外部キーだけに縮む。複合外部キーをアプリ層の検証と列挙テストで代替するなら、ridgepole も候補に戻る。
- **RLS を使わないと決めた場合。** 同上。

## 代替案

### A. ridgepole（Schemafile）に加え、RLS と複合外部キーは別経路の SQL で流す

不採用。理由は次の 4 つ。
- **定義が 2 か所に分かれる。** テナント強制の定義が Schemafile と別の SQL に分かれ、片方の更新漏れがそのまま漏洩の穴になる。
- **ポリシーのずれを検出できない。** ridgepole の差分適用は、別経路で入れたポリシーを見ていない。
- **改名でデータが消えうる。** 列やテーブルの改名は、`renamed_from` を書き忘れると削除＋追加として適用され、データが消える。改名と他の変更を同じ適用に混ぜると、他の変更が検出されない。
- **strong_migrations が使えない。**

### B. Rails マイグレーション＋`schema.rb`

不採用。`execute` で作った RLS ポリシーと複合外部キーが `schema.rb` に残らず、`db:schema:load` で作るテスト DB に再現されない。テストが防壁なしで通るため、要求 2 を満たさない。

### C. Rails の外にある SQL マイグレーションツール（psqldef などの宣言的 SQL、goose・Flyway などの連番 SQL）

不採用。生の SQL で RLS まで定義できる見込みはある（psqldef の RLS 対応は未確認）。しかし、Rails の `db:prepare` やテスト DB 準備との統合と、strong_migrations を失う。Go のプロジェクトが goose を使うのは、Go に標準のマイグレーション機構が無いからである。標準機構を持つ Rails でこれを採ると、標準機構と二重管理になる。
