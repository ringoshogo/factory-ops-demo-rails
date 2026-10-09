# サイクル 01 の計画レビュー：M16〜M20 への反映

`implementation-plan.md` の M16〜M20 を、2 系統の独立レビュー（Claude と Codex）にかけ、指摘を計画に反映した記録である。1 回目（初回）の指摘を反映した計画を、同じ 2 系統でもう一度レビューし（再レビュー）、その指摘を反映した計画を Codex だけで 3 回目にレビューした。M16〜M20 に着手する担当者と、計画のレビューをする人が読む。担当者は、計画の節が「なぜこう書いてあるか」をここで引ける。M15 の指摘は別の作業で扱うので、ここには含めない。

読む順は、マイルストーンごとの判定 → 指摘ごとの対応 → 指摘の根拠を確かめた結果 → 直さなかった指摘（残件の候補）である。指摘の出典は次の形で示す。

| | Claude | Codex |
|---|---|---|
| 初回 | `C<番号>`（Claude の判定の番号。番号の無い Low は `C-Low`） | `X-<マイルストーン>-<順>` |
| 再レビュー | `C2-<記号>`（Claude の判定の `H1`・`M1`・`L1` など） | `X2-<マイルストーン>-<順>` |
| 3 回目 | — | `X3-<マイルストーン>-<順>` |

## 判定

| マイルストーン | 初回 Claude | 初回 Codex | 再レビュー Claude | 再レビュー Codex | 3 回目 Codex |
|---|---|---|---|---|---|
| M16 テストの層と重要シナリオ | Conditional Go | Conditional Go | Go | Conditional Go | Go |
| M17 N+1 の検出 | Conditional Go | No-Go | Conditional Go | No-Go | Go |
| M18 構造化ログと相関 ID | Conditional Go | No-Go | Conditional Go | No-Go | No-Go |
| M19 監査ログ | Conditional Go | No-Go | Conditional Go | Go | Conditional Go |
| M20 スキーマの破壊的変更の検出 | Go | No-Go | Go | No-Go | Go |

Codex が No-Go とした理由は次のとおりである。どれも採用した技術を否定するものではなく、検査が機能しない手順と、先に解消すべき依存が計画に残っていることによる。下の対応で、どれも計画の側を直した。

- **初回**：M17 は Bullet の検出が例外まで届かず、クエリ数の予算が認可の失敗や空の一覧でも通る。M18 はフレームワークのイベントが params・ジョブの引数・例外のメッセージを書き、購読者の例外が捕捉されて検査にならない。M19 は M16 の競合テストの後始末が、追記だけの監査ログと両立しない。M20 は初回の PR で比べる基準が無く、通す手順が無い。
- **再レビュー**：M17 は入れ子を一律「各親に 2 件」とする準備が分納の禁止と衝突する。M18 はジョブの開始・終了のイベントに文脈が付かず、`Rails::Rack::Logger` の文字列のログに値が漏れる。M20 は非破壊の変更を通す規則が、非推奨を経ない enum の値の削除を通す。
- **3 回目**：M18 はジョブの文脈を設定するために引数を先に復元するので、復元の失敗が再試行・破棄の処理と完了のイベントを通らない。開発の環境では文脈のミドルウェアが登録されず、要求に相関 ID が付かない。M19 の Conditional Go は、相関 ID の前提を M18 に置くことによる。

再レビューは、初回の Critical・High の対応を評価した上で新しい指摘を出した。初回の対応のうち、C4・X-M17-1（Bullet の包み）は C2-H1 で、C5・X-M18-1（ログの漏れ）は X2-M18-1 で、C6（文脈の後始末）は X2-M18-2 で、X-M19-1・C9（競合テストの後始末）は C2-M3 で、一部が未解消とされた。ほかの初回の High は解消と判定された。3 回目は、再レビューの指摘の対応を評価した。X2-M18-2（ジョブ・要求の文脈の区間）は、通常の開始・完了を包む位置は正しいが、X3-M18-1・X3-M18-2 が残るとして一部が未解消とされた。ほかの再レビューの High は解消と判定された。

## 指摘と対応

重大度は、2 系統で違うときは高い方を採った。「直した節」は `implementation-plan.md` の節である。各表は、初回の指摘、再レビューの指摘、3 回目の指摘の順に並べる。

### M16

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| X-M16-1 | High | request spec を「成功 1 本＋`UserError` 1 本」に絞る規則に、HTTP の入口でしか確かめられない規則の例外が無い | 作るもの「層への配分の規則」。移すのを「公開 API の spec と同じ業務の分岐」に限り、認証・セッション・認可の配線・トランザクションの単位を request spec に残すと列挙した |
| C3 | High | `bin/test-layers` が JSON の `file_path` で層を決めると、共有の example は定義したファイルに数えられる | 作るもの `bin/test-layers`。層を JSON の `id` のファイルの部分で決める |
| X-M16-2 | Medium | `packs/*/spec` に既存の競合テストがあり、パスで分けると単体に数えられ、M17 の Bullet の対象外（`spec/concurrency` だけ）とも食い違う | 作るもの「競合テストの置き場」と層の表。タグではなくパス（`packs/*/spec/concurrency`）で分け、パスから `:concurrency` のメタデータを導く。rspec の JSON はメタデータを出さないので、層の判定はパスで行う必要がある。M17 の対象外も同じメタデータで決める |
| C11 | Medium | S1 の「すべての ID の入口と mutation」の数え方が未定 | 作るもの「S1 の入口の列挙」。スキーマを走査して ID 型の引数を取る入口を集め、spec の表に無ければ落ちる |
| X-M16-3 | Medium | 「期待を 1 つ外すと落ちる」は検査の有効性を示さない | 完了条件。アプリの防壁（`Partnerships::Access`）と 2 枚の防壁（受注の scope と RLS）の具体的な壊し方と、落ちる example を指定した。受注の scope と RLS はそれぞれ単独で他社の受注を除くので、両方を外す |
| C-Low | Low | `config/ci.rb` に `bin/test-layers` が無い | 作るもの「CI」。`ci.yml` と `config/ci.rb` の両方に足す |
| X2-M16-1 | Medium | `--tag scenario`・`--tag concurrency` の成功は、example が 0 件でも成り立ち、収集を保証しない。M19 の 2 回の実行も同じ | 作るもの「重要シナリオ」と完了条件。`spec/spec_helper.rb` の `config.fail_if_no_examples = true` で 0 件を失敗にする（指摘の `--fail-if-no-examples` は rspec-core 3.13.6 に無い。下の根拠を参照）。`:scenario` も置き場から導いて付け忘れを無くし、S1・S3 のファイルをパスで指定して流す。手の破壊検証は自動の条件の代わりにならないと書いた |

### M17

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| C4・X-M17-1 | High | `start_request`・`end_request` で包むだけでは検出が通知されず、例外にならない。HTTP のミドルウェアとの二重管理、版の固定、検出の検査も無い | 作るもの `spec/support/bullet.rb` と `spec/platform/bullet_spec.rb`。`Bullet.profile`（通知と `ensure` の `end_request` を含む）で包み、`spec/requests` はミドルウェアに任せる。版を `~> 8.2` に固定し、意図的な N+1 を公開 API の直接の呼び出し・Dataloader・HTTP の 3 経路で検出する spec を置く |
| X-M17-2 | High | クエリ数の予算が、認可の失敗・空の一覧・GraphQL のエラーでも通る。ページの件数が 20 未満なら 20 件を解決しない | 作るもの `query_budget_spec.rb`。操作者と変数（`first: 20` を明示）、親と子の作り方、応答の確かめ（`errors` が無い・件数・入れ子が空でない）を先に行い、数える区間を `FactoryOpsSchema.execute` に限る |
| C-Low | Low | 除外の条件が実装と違う（`set_config` を名前 `Tenancy` で流す）。キャッシュの読みも数えてしまう | 同上。除くものを `SCHEMA`・`TRANSACTION`・`Tenancy` と `cached: true` にした |
| X-M17-3 | Medium | 「M14 までの画面の問い合わせ」は成果物として存在せず、対象と入れ子を実装者が決めてしまう。前提の表の「M5」も誤り | 作るもの「画面の問い合わせの一覧」に、M33 の画面の一覧から M14 までの入口で動く 10 の問い合わせ・操作者・親・入れ子を列挙した。一覧の中にコネクションを入れ子にしない規則を足した。前提の表の M17 の行を「M14・M16」に直した |
| C10 | Medium | Bullet は親が 1 件だと N+1 を報告しない | 作るもの「一覧のテストの規則」。親を 2 件以上作る |
| C2-H1 | High | `Bullet.profile` の包みは example が終わった後の `around` で例外を出すので、`bullet_spec` の経路 1・2 の `expect { }.to raise_error` で捕まえられない | 作るもの `spec/support/bullet.rb` と `bullet_spec.rb`。`bullet: false` のメタデータで自動の包みから外し、経路 1・2 は example の中で `Bullet.profile` を呼んで例外を確かめる。経路 3 は `post` 自身が例外を出す |
| C2-M1 | Medium | `Bullet.enable=` はその場で `ActiveRecord::Base` を拡張するので、`test.rb` に直接書くと Active Record が初期化の途中で読み込まれる | 作るもの「Bullet」。test と development の設定を `config.after_initialize` の中に置く |
| X2-M17-1 | High | 入れ子を一律「各親に 2 件」にすると、分納しない `supplierShipments`（出荷依頼ごとに出荷実績 1 件）を業務のデータで作れない | 作るもの `query_budget_spec.rb`「親と子の作り方」。入れ子の件数を問い合わせごとに持ち、`inboundShipments`・`supplierShipments` は発注ごとに 1 件にする。応答の確かめを「作った件数と一致」にした |
| X2-M17-2 | Medium | 親 20 件が同じ関連先を指すと、ソースを外しても読み込みがまとまるかキャッシュに当たり、N+1 を見逃す | 同上「関連先を親ごとに変える」と「負例」。関連先の ID で引く入れ子は親ごとに別の関連先を作る。入れ子ごとにソースの `fetch` をキー 1 つずつの呼び出しに包み、件数が変わることを自動で確かめる。完了条件の手の確認を外した |

### M18

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| C5・X-M18-1 | High | `action_controller.request_started` が params を、ジョブのイベントが引数を、例外のイベントがメッセージを載せる。`filter_parameters` は `query`・`variables`・自由記述を覆わない | 作るもの「イベントごとに書く項目」の表。params を操作名・要約・キーの一覧に置き換え、`ApplicationJob.log_arguments = false`、例外はクラス名だけ、表に無いイベントは `payload` を書かない |
| X-M18-2 | High | 購読者の例外は EventReporter が既定で捕捉するので、テストが落ちない | 書かないもの「ハッシュでないペイロード」。Rails が `raise_on_error` を開発とテストで真にすることと、変えないことを書き、負例を `log_hygiene_spec` に足した（根拠の確認は下） |
| C6 | High | 文脈は、テストとジョブの直接の実行では空に戻らず持ち越される | 作るもの「文脈の後始末」。退避と復元をし、spec の後始末で `clear_context` を呼ぶ。「Rails が空に戻す」を、executor で包まれた処理に限る記述に直した。退避と復元をする位置は、再レビューの X2-M18-2 で `perform_now` に移した |
| X-M18-3 | Medium | 本番のロガーは TaggedLogging でタグを文字列として前に付けるので、行が JSON にならない。検査は末尾の 1 行だけで、`Rails.logger` の漏れを見ない | 作るもの「ロガーの構成」と `log_hygiene_spec`。TaggedLogging で包まない JSON のロガーにして文脈を JSON の中に入れ、本番と同じ構成で 2 つの出口を集め、全行が JSON として読めて禁止の値が無いことを確かめる |
| C-Low | Low | 完了条件の `spec/jobs` に対応する spec が作るものに無い | 作るもの `spec/jobs/log_context_spec.rb` |
| C-Low | Low | `decisions.md` 2 章のエラー通知へのテナント ID が計画に無い | 作るもの「文脈」。`Rails.error.set_context` にも同じ項目を設定する |
| （依頼） | — | `config/ci.rb` での扱い | 完了条件。ログの検査を rspec に置き、`bin/rails runner` の煙の検査を spec に移した。`config/ci.rb` の rspec のステップで流れる |
| X2-M18-1 | High | `Rails::Rack::Logger` は購読ではなく自分で `Rails.logger.info` を呼び、`request.filtered_path` を書く。購読を外しても止まらず、URL の `query`・`variables` の値が残る。JSON の書式は文字列の中の値を消さない | 作るもの「フレームワークの文字列のログ」。止める経路を購読・`Rails::Rack::Logger`・`ActionDispatch::DebugExceptions` の 3 つに列挙し、`Rails::Rack::Logger` を `Platform::RequestContext` に差し替える。`log_hygiene_spec` に、URL の `query`・`variables` に禁止の値を入れた要求と、例外で失敗する要求を足した |
| X2-M18-2 | High | `around_perform` で文脈を設定すると、`active_job.started`（コールバックより前の `_perform_job` で通知）と `active_job.completed`（`perform_now` の計装で通知）に文脈が付かない。コントローラの開始のイベントも action より前に出る | 作るもの「文脈」。ジョブは `ApplicationJob` が上書きする `perform_now` で、要求は `Rails::Rack::Logger` の位置のミドルウェアで文脈を設定する。`request_started` に付くのは `request_id` と相関 ID だけと書いた。`log_context_spec` で、直接の実行とワーカーの経路の両方の開始・完了・失敗・再試行のイベントを確かめ、`correlation_spec` の対象に Rails のイベントを含めた |
| C2-M2 | Medium | フレームワークのログの購読を外す処理が本番の設定にしかなく、`log_hygiene_spec` が本番と同じ構成を通らない | 作るもの「構成の入口」。`Platform::Logging.configure!` にまとめ、`production.rb` と `test.rb` が呼ぶ。ミドルウェアの構成は起動の時点で決まるので、spec からではなくテストの環境から呼ぶ形にした |
| C2-L3 | Low | エラー通知の文脈は executor の push と pop で戻るので、「空に戻す」は不正確 | 作るもの「文脈の後始末」。`Rails.event` は空にし、エラー通知の文脈は push と pop（入れ子を許さない既定では空にする）と書き分け、ジョブではブロックの形の `Rails.error.set_context` で戻す |
| X3-M18-1 | High | `ApplicationJob#perform_now` が `super` の前に `deserialize_arguments_if_needed` で引数を復元すると、復元の失敗が `retry_on`・`discard_on`・`after_discard` を通らず、`active_job.completed` も出ない | 作るもの「文脈」の「ジョブ」と「相関 ID と因果 ID」の「付帯情報の運び方」。付帯情報を引数から外し、`serialize`／`deserialize` のトップレベルの項目としてジョブに持たせ、`perform_now` は引数を復元せずに付帯情報から文脈を設定する。引数の復元は Rails に任せ、Active Job の private のメソッドを呼ばない。イベントの名前と宛先テナントも付帯情報に入れた。`log_context_spec` に、復元に失敗するジョブの破棄・再試行・例外の 3 通りを足した。`adr/005` と `data-model.md` の付帯情報の置き場の記述を、文書に残すことに足した |
| X3-M18-2 | High | ミドルウェアを登録する `Platform::Logging.configure!` を本番とテストだけが呼ぶので、開発の環境で要求の `request_id`・相関 ID が設定されない | 作るもの「構成の入口」。文脈のミドルウェアの登録をログの書式の設定から分け、`config/application.rb` が全環境で `Rails::Rack::Logger` の直前に挿入する。`configure!` は `Rails::Rack::Logger` を消すだけにした。完了条件に、開発の環境のミドルウェアの並びと、要求の開始とイベントの配送が同じ相関 ID で並ぶことの確認を足した |

指摘に無い追加：`ActionDispatch::DebugExceptions` は、捕まえた例外のメッセージを `fatal` で書く。X2-M18-1 と同じ種類の漏れなので、止める経路に入れ、本番とテストのミドルウェアから外す。

### M19

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| X-M19-1・C9 | High | M16 の競合テストは作った行を消すが、監査の行は所有ロールでも消せず、監査の行が指すテナントも消せない | 作るもの「競合テストの後始末」。監査の行とテナントを消さずに残し、テナントを乱数のコードで分ける。完了条件に、制約を有効にしたまま競合テストを同じ DB で 2 回続けて通すことを足した |
| X-M19-2 | Medium | `target:`・`counterparty:` の契約が未定。複数の相手に及ぶ操作と「1 操作 1 行」の両立が決まっていない | 作るもの「mutation の宣言」。ラムダの評価時点と引数を決め、M19 の時点の 9 つの `audit` の mutation の action・対象・相手の表を置いた。複数の相手に及ぶ操作（カタログ）は相手を空にする |
| X-M19-3 | Medium | 「ユーザーエラーでも書き込みが戻る」は入口の仕様と違う（リクエストはコミットされ、セーブポイントだけ戻る）。原子性を確かめるテストが無い | 作るもの「監査の行とコミットの単位」と `audit_spec.rb`。`GraphqlController` と公開 API のセーブポイントの仕様に合わせて書き直し、原子性のテストを 7 つ列挙した |
| C7 | Medium | 同じテナントの中のイベントを受信の記録に入れるかが未定 | 目的の段落と作るもの「イベントの受信」。発行元と宛先が違うときだけ書く |
| C8 | Medium | 列挙テストを「表と一致」にすると、表にあってまだ無い mutation で落ちる | 作るもの「列挙テスト」。スキーマにある mutation が表に無ければ落ち、表にだけある mutation は比べない |
| C2-M3 | Medium | factory の `sequence` はプロセスごとに 1 から数え直すので、テナントを残して 2 回目を流すと一意の制約に当たる。監査の行を作る競合が無いと、2 回の実行が監査の制約を通らない | 作るもの「競合テストの後始末」と完了条件。残す行（テナントとユーザー）の一意の値をすべて乱数にする。`postShipment` を GraphQL から同時に送る `post_shipment_audit_spec.rb` を足した |
| X2-M19-1 | Low | テナントを消せない理由に挙げた「相手テナントの外部キー」は、`data-model.md`（相手テナントへの参照は外部キーを張らない）と食い違う | 同上。所有テナントは外部キーで消せないこと、相手テナントは消せるが監査の行が指すので残すことを分けて書いた |
| C2-L1 | Low | 前提の表の M19 に M16 が無い | 「マイルストーンの一覧」の前提の表。M19 の前提を「M16・M18」にし、理由に競合テストの後始末を足した |
| C2-L2 | Low | `decisions.md` 2 章「監査」の対象の定義が古いままで、文書に残すことに無い | 文書に残すこと。対象の定義を「相手テナントに効果が及ぶ書き込み」に、記録する場所を 2 つの基底クラスに直す |

指摘に無い追加：行のトリガーは `TRUNCATE` で動かず、所有ロールが監査の行を消せる。追記だけの保証の穴なので、`TRUNCATE` を拒む文単位のトリガーを M19 の作るものと `spec/db/audit_logs_spec.rb` に足した。

### M20

| 出典 | 重大度 | 指摘 | 直した節と内容 |
|---|---|---|---|
| X-M20-1・C13 | High | M20 で初めて `schema.graphql` を作るので、基準との比較が初回の PR で成り立たない | 作るもの「初回の導入」と `bin/check-schema-compat`。M20 を 2 つの PR に分け、CI のステップは 2 つ目で足す。基準に `schema.graphql` が無ければ失敗する（C13 の「無ければ通す」は採らなかった。下の残件の候補を参照） |
| X-M20-2 | Medium | 型の変更・必須の引数の追加の移行が未定で、例外に流れうる | 作るもの「互換の判定」。型の変更と必須の追加は非推奨を経ても通さず、新しいフィールドを足して古いものを非推奨にする方針を書いた。削除の変更の種類を列挙し、型の削除の条件も決めた |
| X-M20-3・C12 | Medium | 比較器の独自の判定と例外の一覧の判定に自動テストが無く、手での確認は削除 1 件だけである | 作るもの `spec/graphql/schema_compat_spec.rb`。新旧の小さな SDL で全分岐を確かめ、手での確認を外した。判定を `lib/schema_compat.rb` に分けて spec から呼ぶ |
| X-M20-3 | Medium | 例外を比較の文言で識別すると、別の変更を通しうる。理由の無い行も通る | 作るもの「互換の判定」。例外を変更のクラス名とスキーマの座標で識別し、`reason` の無い行を拒み、一致しない行はその変更を通さない |
| C-Low | Low | `config/ci.rb` に `bin/check-schema-compat` が無い | 作るもの「CI」 |
| X2-M20-1 | High | 「非破壊の変更は通す」と「削除は非推奨だったときに通す」の順が未定で、比較器が非破壊に分類する出力だけの enum の値の削除が、非推奨を経ずに通る | 作るもの「互換の判定」。規則を順に当てる形にし、削除の規則を比較器の重大度より先に当てる。spec に、出力だけの enum と入力に使う enum の両方で非推奨でない値の削除を落とす場合を足した |
| X2-M20-2 | Medium | 例外の一覧が「上のどれにも当たらない破壊的変更」にしか当たらず、秘密を漏らすフィールドの即時削除（削除の規則で落ちる）に使えるかが不明 | 同上「例外の一覧」。規則で落とした変更すべてに当て、非推奨でないフィールドの削除を例外の行で通す場合を spec に足した |
| C2-L4 | Low | 「型の変更は通さない」に、比較器が非破壊とする型の変更（`SafeTypeChange`）を含むかが曖昧 | 同上「型の変更」。比較器が非破壊とする変更（出力の非 null 化・入力の null 可化）は通し、それ以外を落とす。spec に出力の非 null 化を足した |

## 指摘の根拠を確かめた結果

指摘の根拠は、インストール済みの gem（Rails 8.1.4・rspec-core 3.13.6）と、取得した gem の源（Bullet 8.2.0・graphql-schema_comparator 1.2.1）で確かめた。初回の根拠、再レビューの根拠、3 回目の根拠の順に並べる。

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
| `rspec --fail-if-no-examples` で 0 件の実行を落とせる（X2-M16-1） | 一部が誤り。rspec-core 3.13.6 は `fail_if_no_examples` を設定（`add_setting`）としてだけ持ち、コマンドラインの引数は無い。計画は `spec_helper.rb` の設定で同じことをする |
| `Bullet.profile` の例外は `around` の中で起き、example の中では捕まえられない。経路 3 は `post` が例外を出す（C2-H1） | 正しい。`profile` は `yield` の後に通知する。`Bullet::Rack` は Railtie が `middleware.use` で足すので `ShowExceptions` の内側にあり、`:rescuable` は対応表に無い例外を投げ直す |
| `Bullet.enable=` がその場で Active Record を拡張する（C2-M1） | 正しい。`enable=` が `Bullet::ActiveRecord.enable` を呼び、`require 'active_record'` と `ActiveRecord::Base.extend` を行う |
| `Rails::Rack::Logger` が `filtered_path` を直接書く（X2-M18-1） | 正しい。`call_app` が `logger.info { started_request_message(request) }` を呼ぶ。このミドルウェアの `request.action_dispatch` の計装には、Rails 8.1.4 の中に購読者が無い |
| `active_job.started` はコールバックより前、`completed` は `perform_now` の計装で通知される。コントローラの開始も action より前（X2-M18-2） | 正しい。`Instrumentation#_perform_job` は `perform_start` を通知してから `super`（`run_callbacks :perform`）を呼ぶ。`Instrumentation#perform_now` は `perform` の計装で包み、再試行と破棄の通知もその中の `rescue_with_handler` から出る。`ApplicationJob` で上書きした `perform_now` は、`ActiveJob::Base` が include するどのモジュールよりも外側にあり、ワーカーの `ActiveJob::Base.execute` も `perform_now` を呼ぶ。コントローラは `process_action` の入口で `start_processing` を通知してから、コールバックを含む `super` を呼ぶ |
| エラー通知の文脈は executor の push と pop で戻る（C2-L3） | 一部が正しい。executor は `ExecutionContext.push` と `pop` を呼ぶが、入れ子を許さない既定（`nestable` が偽）では、どちらも空にする。`ActiveSupport::TestCase` で `executor_around_test_case` を有効にしたときだけ前の値に戻る |
| factory の `sequence` はプロセスごとに数え直す（C2-M3） | 正しい。テナントの `code` とユーザーの `email` が `sequence` で、どちらも一意である |
| 分納しないので、発注ごとの出荷実績は 1 件（X2-M17-1） | 正しい。`shipments.shipment_request_id` と `shipment_requests.sales_order_id` が一意である |
| 関連先の ID で引くソースは、同じ関連先の親では読み込みがまとまる（X2-M17-2） | 正しい。`Sources::PublicApiSource` はキー（関連先の ID）をまとめて公開 API を 1 回呼ぶ。`lines` などは親の ID で引くので、親ごとに違う |
| 出力だけの enum の値の削除は `non_breaking` に分類される（X2-M20-1） | 正しい。`EnumValueRemoved` は、enum が入力に使われるときだけ破壊的にする |
| 型の変更に、比較器が非破壊とするものがある（C2-L4） | 正しい。`FieldTypeChanged`・`FieldArgumentTypeChanged`・`InputFieldTypeChanged` は `SafeTypeChange` で、出力の非 null 化と入力の null 可化を非破壊に分類する |
| 相手テナントへの参照に外部キーは無い（X2-M19-1） | 正しい。`data-model.md` は相手テナントへの参照を「→」（外部キーを張らない ID の参照）にし、`audit_logs.counterparty_tenant_id` も「→」である。`owner_tenant_id` は `create_tenant_table` が `tenants` への外部キーを付ける |
| 引数を先に復元すると、復元の失敗が Active Job の例外の処理と計装を通らない（X3-M18-1） | 正しい。`Execution#perform_now` は、実行回数の加算と `deserialize_arguments_if_needed` を `rescue_with_handler` と `run_after_discard_procs` の内側で行い、`Instrumentation#perform_now` がその外側を `perform` の計装で包む。`ActiveJob::Base#deserialize` は引数を `serialized_arguments` に入れるだけで、復元は `perform_now` まで遅れる。`serialize` に `super.merge` で項目を足し、`deserialize` で `super` の後に読む上書きは、`ActiveJob::Core` の文書にある作法である。トップレベルの項目から文脈を設定する形を最小の再現で動かし、GlobalID の復元の失敗で `discard_on` と `after_discard`、`retry_on` と再登録した付帯情報、`active_job.discarded`・`retry_scheduled`・`completed` の文脈を確かめた |
| 開発の環境には文脈のミドルウェアが無い（X3-M18-2） | 正しい。Rails の既定のスタックは `ActionDispatch::RequestId` と `Rails::Rack::Logger` を登録するが、`RequestId` は env に値を入れるだけで `Rails.event` の文脈に入れない。`config.middleware` の `insert_before` は `MiddlewareStack#insert`（`insert_before` はその別名）に渡り、`MiddlewareStackProxy#merge_into` は挿入と差し替えをすべて当ててから削除を当てるので、全環境で挿入した `Platform::RequestContext` は、本番とテストで `Rails::Rack::Logger` を消してもその位置に残る |

## 残件の候補

直さなかった指摘と、M16〜M20 の外の節に残る食い違いである。台帳（`docs/plans/open-items.md`）に載せるかは、台帳の担当が決める。

- **request spec の削減を機械で検査しない**（C12 の M16 の部分）：公開 API の spec と同じ業務の分岐かどうかは意味の比較で、機械で判定できない。計画は残す規則を列挙し、判定をレビューに任せる。
- **基準に `schema.graphql` が無いときに比べずに通す**（C13 の直し方）：通常の運用で基準のファイルが消えたときにも検査が素通りするので採らず、初回の導入を 2 つの PR に分けた（X-M20-1）。
- **M33 の画面 18 との食い違い**：M17 は一覧の中にコネクションを入れ子にしない規則にしたので、M33 の「`/buyer/suppliers` 取引先とカタログ」は、取引先を選んでからカタログを引く形になる。M33 の画面の一覧の記述をこれに合わせる必要がある。
- **`audit_logs.actor_user_id` の参照の種類**：`data-model.md` は `actor_user_id` に「→」を付けていないが、ユーザーは `platform` の外の表で、コンテキストをまたぐ参照は外部キーを張らない規則である。M19 は、どちらでも成り立つようにユーザーを消さずに残す。`data-model.md` の記述をどちらかに揃える必要がある。
- **`ApplicationJob#perform_now` が Rails の private のメソッドに頼る**：ワーカーの経路で引数を先に戻すのに `deserialize_arguments_if_needed` を呼ぶ。Rails の版上げで名前か挙動が変わると、`log_context_spec` のワーカーの経路が落ちて気づける。
