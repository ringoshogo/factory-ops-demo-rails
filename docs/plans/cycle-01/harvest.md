# サイクル 01 の知見の収穫

サイクル 01（M15〜M20）の実装で分かったことのうち、正本に無いものを正本へ書いた記録である。手順は `guides/cycle-end.md`「2. 知見の収穫」にある。逸脱検査（`conformance.md`）は、ここで足した正本を含めて成果物と突き合わせる。再発防止（`recurrence.md`）は、ここにある知見を 2 度書かない。

読んだものは、サイクルの diff（`git diff e72af36..cycle-01-end`）、振り返りの想定外（`retrospective.md`）、台帳の `judgment` の行（OI-19〜OI-49）、実装レビューの証跡の「実装の記録」、正本（`architecture/`・`adr/`・`guides/`・`README.md`「開発環境」）である。マイルストーンの中で正本に書き足した分は済んでいるので、ここではその漏れを拾った。

## 正本に書いた項目

| 層 | 項目 | 分類 | 正本の状態 | 書いた文書と節・内容 | 根拠 |
|---|---|---|---|---|---|
| 表とマイグレーション | 監査の行の `occurred_at` は DB の既定値で埋め、値を固定するトリガーは置かない（OI-45） | 決定（ADR にしない。行の中に理由を 1 文） | 無い | `architecture/data-model.md`「監査ログ（`platform`）」の「追記だけにする仕組み」。アプリは時刻を渡さず、固定のトリガーを置かないので過去の時刻の行を書けてすぐ消せること、固定すると保存期間の spec が行を作れないこと | `b72c0aa` |
| ジョブとイベント | mutation の入口は要求だけで、監査の行は相関 ID を必須にする。要求の外から mutation を流す入口を足す人は、相関 ID の始め方を同じ変更で決める（OI-42） | 作り方 | 無い（相関 ID の始め方は、要求とイベントだけを書いていた） | `guides/config.md`「相関 ID と因果 ID」の相関 ID の項 | `b72c0aa`・`de9d435` |
| GraphQL | スキーマに `extra_types` で型を足さない。graphql-ruby 2.6 の書き出しが同じ型を 2 回書く（OI-47） | 作り方 | 無い。外したことはコードに残らず、足し直しても書き出しの検査は落ちない | `architecture/graphql-schema.md`「スキーマの変更と非推奨」の書き出しの段落 | `b72af2f` |
| CI と設定 | 自動読み込みの除外に `schema_compat.rb` を足した | 作り方 | 不正確。除外を `rubocop` だけと書いていた | `guides/config.md`「application.rb で変えたこと」。2 つとも開発とテストのグループにしかない gem を読むので、本番の起動では読めない | `b72af2f` |
| CI と設定 | カスタム Cop `FactoryOps/NoHistoryComment` を足した | 手順 | 不正確。`bin/rubocop` の行が `FactoryOps/EventJobEnqueue` だけを挙げていた | `guides/bin.md`「コミットの前に流す検査」の `bin/rubocop` の行。参照に `guides/comments.md`「機械で止めるもの」を足した | `a557e1b` |

## 書かなかった項目

| 層 | 項目 | 理由 |
|---|---|---|
| 表とマイグレーション | アプリのロールから `audit_logs` の UPDATE・DELETE を外す、保存期間の関数の `search_path` を固定する | 正本にある（`data-model.md`「監査ログ（`platform`）」） |
| 表とマイグレーション | 表の行列で `audit_logs` を追記だけの表として扱う（OI-41） | 実装の手段。行列の期待値の定数とコメントから同じ意図を読める |
| 表とマイグレーション | 実装は「出荷停止中」を導出しないが、`graphql-schema.md`「状況の enum」に値がある | 収穫ではなく、正本と実装のどちらが正かの裁定が要る。逸脱検査に回す |
| 公開 API | 照合し直す受注の明細を 1 回で引く、ロックの順 | 正本にある（`graphql-schema.md`「ページングと N+1」、`data-model.md`） |
| 公開 API | `buyer.supplier` が関係の無い相手で `null` を返す、在庫の調整が品目の存在を自分で確かめない（OI-01・OI-20・OI-25） | 正本にある（`graphql-schema.md`「ID と `node`」・mutation の一覧） |
| 公開 API | 在庫のパッケージが一括の書き込みを使わない（OI-02） | 実装の手段。在庫のモデルの spec の検査とコメントにある |
| 公開 API | 業務の分岐を単体へ移し、照合待ちの結合の example を残す（OI-22・OI-49） | 規則は正本にある（`guides/testing.md`「層への配分」）。個別の判断は台帳の記録で足りる |
| policy | 出荷の認可で、付与を与えている受注側の集合を 1 回だけ引いて覚える | 正本にある（`graphql-schema.md`「ページングと N+1」） |
| policy | 監査ログの policy の scope に所有テナントの条件を持たせる | 正本にある（`graphql-schema.md`「監査ログ」） |
| GraphQL | 監査の行の対象・型の名前・視点・時刻の境界（OI-37〜OI-40・OI-44） | 正本にある（`graphql-schema.md`「監査ログ」） |
| GraphQL | 型の削除の参照の数え方、例外の行の照らし方（OI-46・OI-48） | 正本にある（`graphql-schema.md`「互換の判定」「例外の一覧」） |
| GraphQL | 予算のテストで `first` をコネクションにだけ渡す（OI-27） | 実装の手段。予算の spec の問い合わせの表から読める |
| ジョブとイベント | 止めた購読、エラー通知の送り方、文脈の置き換え、相関 ID の始まり、結果の種類、分離の単位、本番の水準の制限（OI-28〜OI-31・OI-34〜OI-36） | 正本にある（`guides/config.md`「ログ」） |
| ジョブとイベント | 購読者が書き込み先の `Pathname` に書くたびにファイルを作り直していた | 実装の手段。追記で開く初期化と、追記を確かめる spec が守る |
| テスト | factory の間は Bullet の検出を止める、Bullet は関連の読み込みしか見ない（OI-26） | 正本にある（`graphql-schema.md`「ページングと N+1」）。止め方は `spec/support/bullet.rb` のコメントにある |
| テスト | ワーカーの経路を実行器の中で流す（OI-32）、テストの環境の `DebugExceptions` は書く前に例外を送出し直す（OI-33） | 実装の手段。どちらも spec のコメントにある |
| テスト | 層の置き場、割合の数え始め、競合テストの後始末、一意の値を乱数で作る、0 件の実行を失敗にする（OI-19・OI-21・OI-23・OI-24） | 正本にある（`guides/testing.md`） |
| テスト | `audit:purge` は所有ロールの接続に張り替えるので、spec から流さない（OI-43） | 分類に確信が持てない。作り方として `guides/testing.md` に置くか、タスクのコメントで足りるかを決められないので、次のサイクルへ送る |
| テスト | 壊しても落ちなかった事例（行ロックだけ、冪等キーの確かめだけ、`around_perform`） | 事例は証跡の観測である。多重の防壁は設計文書にあり、`around_perform` の件は `guides/config.md` にある。壊しても落ちないテストが繰り返し出たことは、回し方の問題として振り返りから再発防止へ渡す |
| テスト | 予算の負例で、データの読み込みのソースを差し替える方法 | 実装の手段。spec のコードから読める |
| CI と設定 | Bullet を開発ではログ、テストでは例外にする | 正本にある（`guides/config.md`「環境ごとの設定」）。理由は環境の設定のコメントにある |
| CI と設定 | 台帳と層の検査を CI に入れた、PR の本文を環境変数で渡す | 正本にある（`guides/bin.md`、`guides/config.md`「CI の工程」）。本文の渡し方は CI の定義のコメントにある |
| CI と設定 | `bin/check-schema-compat` をまだ CI で流していない | 正本にある（`guides/bin.md`、`graphql-schema.md`「互換の判定」）。CI のステップは M20 の 2 つ目の PR で足す |

振り返りの想定外のうち、計画の節に残った古い記述と、一部にだけ当てた参照の直しは、正本の知見ではなく成果物と正本の食い違いなので、逸脱検査と再発防止に渡す。

## 見た層

| 層 | 見たもの | 書いた項目 |
|---|---|---|
| 表とマイグレーション | 監査ログの表と関数の 2 つのマイグレーション、`structure.sql`、権限のタスク、コメントだけを直したマイグレーション | OI-45 |
| 公開 API | 取引関係・受注・在庫・出荷の公開 API と状況の導出、監査ログの公開 API | 無し |
| policy | 出荷の認可、監査ログの policy | 無し |
| GraphQL | 基底 mutation・コントローラ・型・リゾルバ・`schema.graphql`・互換の判定 | OI-47 |
| ジョブとイベント | `ApplicationJob`・イベントのジョブ・`Contracts.publish`・ログの部品 | OI-42 |
| テスト | spec の追加・移動・削除と `spec/support` | 無し（OI-43 は送った） |
| CI と設定 | CI の定義・`config/ci.rb`・`.rubocop.yml`・`Gemfile`・`config/application.rb`・環境の設定・rake タスク | 自動読み込みの除外、`bin/rubocop` の行 |
