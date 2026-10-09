# サイクル 01 の計画レビュー：M16〜M20 への反映

`implementation-plan.md` の M16〜M20 を、2 系統の独立レビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。M16〜M20 に着手する担当者と、計画のレビューをする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。M15 の指摘は別の作業で扱うので、ここには含めない。

読む順は、マイルストーンごとの判定 → 指摘ごとの対応 → 指摘の根拠を確かめた結果 → 直さなかった指摘（残件の候補）である。指摘の出典は、Claude の指摘を `C<番号>`（Claude の判定の番号。番号の無い Low は `C-Low`）、Codex の指摘を `X-<マイルストーン>-<順>` で示す。

## 判定

| マイルストーン | Claude | Codex | Codex が No-Go とした理由 |
|---|---|---|---|
| M16 テストの層と重要シナリオ | Conditional Go | Conditional Go | — |
| M17 N+1 の検出 | Conditional Go | No-Go | Bullet の検出が例外まで届かず、クエリ数の予算が認可の失敗や空の一覧でも通る |
| M18 構造化ログと相関 ID | Conditional Go | No-Go | フレームワークのイベントが params・ジョブの引数・例外のメッセージを書き、購読者の例外が捕捉されて検査にならない |
| M19 監査ログ | Conditional Go | No-Go | M16 の競合テストの後始末が、追記だけの監査ログと両立しない |
| M20 スキーマの破壊的変更の検出 | Go | No-Go | 初回の PR で比べる基準が無く、通す手順が無い |

Codex の No-Go は、採用した技術を否定するものではなく、検査が機能しない手順と、先に解消すべき依存が計画に残っていることによる。下の対応で、どれも計画の側を直した。

## 指摘と対応

重大度は、2 系統で違うときは高い方を採った。「直した節」は `implementation-plan.md` の節である。

### M16

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| X-M16-1 | High | request spec を「成功 1 本＋`UserError` 1 本」に絞る規則に、HTTP の入口でしか確かめられない規則の例外が無い | 作るもの「層への配分の規則」。移すのを「公開 API の spec と同じ業務の分岐」に限り、認証・セッション・認可の配線・トランザクションの単位を request spec に残すと列挙した |
| C3 | High | `bin/test-layers` が JSON の `file_path` で層を決めると、共有の example は定義したファイルに数えられる | 作るもの `bin/test-layers`。層を JSON の `id` のファイルの部分で決める |
| X-M16-2 | Medium | `packs/*/spec` に既存の競合テストがあり、パスで分けると単体に数えられ、M17 の Bullet の対象外（`spec/concurrency` だけ）とも食い違う | 作るもの「競合テストの置き場」と層の表。タグではなくパス（`packs/*/spec/concurrency`）で分け、パスから `:concurrency` のメタデータを導く。rspec の JSON はメタデータを出さないので、層の判定はパスで行う必要がある。M17 の対象外も同じメタデータで決める |
| C11 | Medium | S1 の「すべての ID の入口と mutation」の数え方が未定 | 作るもの「S1 の入口の列挙」。スキーマを走査して ID 型の引数を取る入口を集め、spec の表に無ければ落ちる |
| X-M16-3 | Medium | 「期待を 1 つ外すと落ちる」は検査の有効性を示さない | 完了条件。アプリの防壁（`Partnerships::Access`）と 2 枚の防壁（受注の scope と RLS）の具体的な壊し方と、落ちる example を指定した。受注の scope と RLS はそれぞれ単独で他社の受注を除くので、両方を外す |
| C-Low | Low | `config/ci.rb` に `bin/test-layers` が無い | 作るもの「CI」。`ci.yml` と `config/ci.rb` の両方に足す |

### M17

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| C4・X-M17-1 | High | `start_request`・`end_request` で包むだけでは検出が通知されず、例外にならない。HTTP のミドルウェアとの二重管理、版の固定、検出の検査も無い | 作るもの `spec/support/bullet.rb` と `spec/platform/bullet_spec.rb`。`Bullet.profile`（通知と `ensure` の `end_request` を含む）で包み、`spec/requests` はミドルウェアに任せる。版を `~> 8.2` に固定し、意図的な N+1 を公開 API の直接の呼び出し・Dataloader・HTTP の 3 経路で検出する spec を置く |
| X-M17-2 | High | クエリ数の予算が、認可の失敗・空の一覧・GraphQL のエラーでも通る。ページの件数が 20 未満なら 20 件を解決しない | 作るもの `query_budget_spec.rb`。操作者と変数（`first: 20` を明示）、親と子の作り方、応答の確かめ（`errors` が無い・件数・入れ子が空でない）を先に行い、数える区間を `FactoryOpsSchema.execute` に限る |
| C-Low | Low | 除外の条件が実装と違う（`set_config` を名前 `Tenancy` で流す）。キャッシュの読みも数えてしまう | 同上。除くものを `SCHEMA`・`TRANSACTION`・`Tenancy` と `cached: true` にした |
| X-M17-3 | Medium | 「M14 までの画面の問い合わせ」は成果物として存在せず、対象と入れ子を実装者が決めてしまう。前提の表の「M5」も誤り | 作るもの「画面の問い合わせの一覧」に、M33 の画面の一覧から M14 までの入口で動く 10 の問い合わせ・操作者・親・入れ子を列挙した。一覧の中にコネクションを入れ子にしない規則を足した。前提の表の M17 の行を「M14・M16」に直した |
| C10 | Medium | Bullet は親が 1 件だと N+1 を報告しない | 作るもの「一覧のテストの規則」。親を 2 件以上作る |

### M18

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| C5・X-M18-1 | High | `action_controller.request_started` が params を、ジョブのイベントが引数を、例外のイベントがメッセージを載せる。`filter_parameters` は `query`・`variables`・自由記述を覆わない | 作るもの「イベントごとに書く項目」の表。params を操作名・要約・キーの一覧に置き換え、`ApplicationJob.log_arguments = false`、例外はクラス名だけ、表に無いイベントは `payload` を書かない |
| X-M18-2 | High | 購読者の例外は EventReporter が既定で捕捉するので、テストが落ちない | 書かないもの「ハッシュでないペイロード」。Rails が `raise_on_error` を開発とテストで真にすることと、変えないことを書き、負例を `log_hygiene_spec` に足した（根拠の確認は下） |
| C6 | High | 文脈は、テストとジョブの直接の実行では空に戻らず持ち越される | 作るもの「文脈の後始末」。`around_perform` で退避と復元をし、spec の後始末で `clear_context` を呼ぶ。「Rails が空に戻す」を、executor で包まれた処理に限る記述に直した |
| X-M18-3 | Medium | 本番のロガーは TaggedLogging でタグを文字列として前に付けるので、行が JSON にならない。検査は末尾の 1 行だけで、`Rails.logger` の漏れを見ない | 作るもの「ロガーの構成」と `log_hygiene_spec`。TaggedLogging で包まない JSON のロガーにして文脈を JSON の中に入れ、本番と同じ構成で 2 つの出口を集め、全行が JSON として読めて禁止の値が無いことを確かめる |
| C-Low | Low | 完了条件の `spec/jobs` に対応する spec が作るものに無い | 作るもの `spec/jobs/log_context_spec.rb` |
| C-Low | Low | `decisions.md` 2 章のエラー通知へのテナント ID が計画に無い | 作るもの「文脈」。`Rails.error.set_context` にも同じ項目を設定する |
| （依頼） | — | `config/ci.rb` での扱い | 完了条件。ログの検査を rspec に置き、`bin/rails runner` の煙の検査を spec に移した。`config/ci.rb` の rspec のステップで流れる |

### M19

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| X-M19-1・C9 | High | M16 の競合テストは作った行を消すが、監査の行は所有ロールでも消せず、監査の行が指すテナントも消せない | 作るもの「競合テストの後始末」。監査の行とテナントを消さずに残し、テナントを乱数のコードで分ける。完了条件に、制約を有効にしたまま競合テストを同じ DB で 2 回続けて通すことを足した |
| X-M19-2 | Medium | `target:`・`counterparty:` の契約が未定。複数の相手に及ぶ操作と「1 操作 1 行」の両立が決まっていない | 作るもの「mutation の宣言」。ラムダの評価時点と引数を決め、M19 の時点の 9 つの `audit` の mutation の action・対象・相手の表を置いた。複数の相手に及ぶ操作（カタログ）は相手を空にする |
| X-M19-3 | Medium | 「ユーザーエラーでも書き込みが戻る」は入口の仕様と違う（リクエストはコミットされ、セーブポイントだけ戻る）。原子性を確かめるテストが無い | 作るもの「監査の行とコミットの単位」と `audit_spec.rb`。`GraphqlController` と公開 API のセーブポイントの仕様に合わせて書き直し、原子性のテストを 7 つ列挙した |
| C7 | Medium | 同じテナントの中のイベントを受信の記録に入れるかが未定 | 目的の段落と作るもの「イベントの受信」。発行元と宛先が違うときだけ書く |
| C8 | Medium | 列挙テストを「表と一致」にすると、表にあってまだ無い mutation で落ちる | 作るもの「列挙テスト」。スキーマにある mutation が表に無ければ落ち、表にだけある mutation は比べない |

指摘に無い追加：行のトリガーは `TRUNCATE` で動かず、所有ロールが監査の行を消せる。追記だけの保証の穴なので、`TRUNCATE` を拒む文単位のトリガーを M19 の作るものと `spec/db/audit_logs_spec.rb` に足した。

### M20

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| X-M20-1・C13 | High | M20 で初めて `schema.graphql` を作るので、基準との比較が初回の PR で成り立たない | 作るもの「初回の導入」と `bin/check-schema-compat`。M20 を 2 つの PR に分け、CI のステップは 2 つ目で足す。基準に `schema.graphql` が無ければ失敗する（C13 の「無ければ通す」は採らなかった。下の残件の候補を参照） |
| X-M20-2 | Medium | 型の変更・必須の引数の追加の移行が未定で、例外に流れうる | 作るもの「互換の判定」。型の変更と必須の追加は非推奨を経ても通さず、新しいフィールドを足して古いものを非推奨にする方針を書いた。削除の変更の種類を列挙し、型の削除の条件も決めた |
| X-M20-3・C12 | Medium | 比較器の独自の判定と例外の一覧の判定に自動テストが無く、手での確認は削除 1 件だけである | 作るもの `spec/graphql/schema_compat_spec.rb`。新旧の小さな SDL で全分岐を確かめ、手での確認を外した。判定を `lib/schema_compat.rb` に分けて spec から呼ぶ |
| X-M20-3 | Medium | 例外を比較の文言で識別すると、別の変更を通しうる。理由の無い行も通る | 作るもの「互換の判定」。例外を変更のクラス名とスキーマの座標で識別し、`reason` の無い行を拒み、一致しない行はその変更を通さない |
| C-Low | Low | `config/ci.rb` に `bin/check-schema-compat` が無い | 作るもの「CI」 |

## 指摘の根拠を確かめた結果

指摘の根拠は、インストール済みの gem（Rails 8.1.4・rspec-core）と、取得した gem の源（Bullet 8.2.0・graphql-schema_comparator 1.2.1）で確かめた。

| 根拠 | 結果 |
|---|---|
| Bullet は `perform_out_of_channel_notifications` を呼ばないと例外にならず、`end_request` が状態を消す（C4・X-M17-1） | 正しい。`Bullet.profile` が、開始・通知・`ensure` の `end_request` をまとめて行うので、計画はこれを使う。`Bullet::Rack` は `start_request` で状態を作り直すので、外で包むと二重管理になる |
| Bullet は 1 件のレコードを N+1 の候補にしない（C10） | 正しい。1 件の読み込みは `add_impossible_object` に入る |
| `Rails.event.raise_on_error` は既定で偽で、購読者の例外が捕捉される（X-M18-2） | 一部が誤り。`EventReporter` の既定は偽だが、Rails の起動の処理が `raise_on_error = config.consider_all_requests_local` を設定し、本リポジトリの開発とテストでは真になる。設定を足す直し方は採らず、この依存を計画に書き、負例の spec で固定した。文字列の名前とハッシュでない値を渡すと購読者の前で `notify` 自身が失敗するので、購読者に届くハッシュでないペイロードはイベントのオブジェクトだけである |
| `ActiveJob` の `log_arguments` の既定が真で、構造化イベントが引数と例外のメッセージを載せる（X-M18-1） | 正しい |
| `action_controller.request_started` が params を載せる（C5） | 正しい。内部の項目だけを除いて、残りの params をそのまま載せる |
| 文脈は executor の終わりにだけ空に戻る（C6） | 正しい。`ActiveSupport::Railtie` が executor の完了で `clear_context` を呼ぶ |
| 本番の TaggedLogging がタグを JSON の前に付ける（X-M18-3） | 正しい。TaggedLogging は書式の前でメッセージにタグを付ける。Rails は `config.logger` を TaggedLogging で包まず、要求とジョブのログは `tagged` を持たないロガーにタグを付けない |
| JSON の `file_path` は共有の example で定義したファイルを指す（C3） | 正しい。JSON は `id` と `file_path` を出し、メタデータ（タグ）は出さない |
| graphql-schema_comparator の変更がクラスと `path` を持ち、非推奨のフィールドの削除も破壊的に分類する（X-M20-3・Claude の確認事項） | 正しい。必須の引数・入力項目の追加は破壊的、出力だけの enum の値の削除は非破壊に分類される |

## 残件の候補

直さなかった指摘と、M16〜M20 の外の節に残る食い違いである。台帳（`docs/plans/open-items.md`）に載せるかは、台帳の担当が決める。

- **request spec の削減を機械で検査しない**（C12 の M16 の部分）：公開 API の spec と同じ業務の分岐かどうかは意味の比較で、機械で判定できない。計画は残す規則を列挙し、判定をレビューに任せる。
- **基準に `schema.graphql` が無いときに比べずに通す**（C13 の直し方）：通常の運用で基準のファイルが消えたときにも検査が素通りするので採らず、初回の導入を 2 つの PR に分けた（X-M20-1）。
- **M33 の画面 18 との食い違い**：M17 は一覧の中にコネクションを入れ子にしない規則にしたので、M33 の「`/buyer/suppliers` 取引先とカタログ」は、取引先を選んでからカタログを引く形になる。M33 の画面の一覧の記述をこれに合わせる必要がある。
