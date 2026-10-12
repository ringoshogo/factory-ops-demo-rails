require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/cop/factory_ops/no_history_comment"

# コメントに経緯・マイルストーンの番号・台帳の ID・予定を書かせない。止める例と通す例は docs/guides/comments.md「このリポジトリの例」「機械で止めるもの」にそろえる
RSpec.describe RuboCop::Cop::FactoryOps::NoHistoryComment, :config do
  def message(term)
    "コメントに経緯・マイルストーンの番号・台帳の ID・予定を書かない（#{term}）。いまの振る舞いと理由だけを書く（docs/guides/comments.md）。"
  end

  it "guides/comments.md の悪い例を、マイルストーンの番号で落とす" do
    expect_offense(<<~RUBY, m14: message("M14"), m15: message("M15"), m12: message("M12"))
      # 受注側が所有する出荷実績。発注側が読む SupplierShipment（M14）とは別の型にする
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ %{m14}
      status = derive # 「出荷停止中」は M15 で足す
                      ^^^^^^^^^^^^^^^^^^ %{m15}
      # 受注の引当（docs/implementation-plan.md M12 の完了条件）
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ %{m12}
    RUBY
  end

  it "和文に挟まった番号も落とす" do
    expect_offense(<<~RUBY, m15: message("M15"), m3: message("M3"))
      # 停止中はM15で足す
      ^^^^^^^^^^^^ %{m15}
      # 経路M3で読む
      ^^^^^^^^^ %{m3}
    RUBY
  end

  it "経緯の語を落とす" do
    expect_offense(<<~RUBY, a: message("以前は"), b: message("レビューで"), c: message("指摘で"), d: message("を直した"), e: message("当初は"))
      # 以前は別の表に置いていた
      ^^^^^^^^^^^^^^ %{a}
      # レビューで分けた
      ^^^^^^^^^^ %{b}
      # 指摘で順序を変えた
      ^^^^^^^^^^^ %{c}
      # バグを直した
      ^^^^^^^^ %{d}
      # 当初は同期で送っていた
      ^^^^^^^^^^^^^ %{e}
    RUBY
  end

  it "台帳の ID を落とす" do
    expect_offense(<<~RUBY, oi: message("OI-35"), ib: message("IB-25"))
      # 文脈をスレッドごとに持つことを前提にする（OI-35）
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ %{oi}
      # 上限ちょうどと上限 + 1 を仕様の値で書く（IB-25）
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ %{ib}
    RUBY
  end

  it "TODO と FIXME を落とす" do
    expect_offense(<<~RUBY, todo: message("TODO"), fixme: message("FIXME"))
      # TODO: あとで消す
      ^^^^^^^^^^^^^ %{todo}
      # FIXME 遅い
      ^^^^^^^^^^ %{fixme}
    RUBY
  end

  it "複数行のコメントは、語を含む行を落とす" do
    expect_offense(<<~RUBY, msg: message("M14"))
      # 発注側が読む出荷実績は、
      # 経路 3 の写しである（M14）
      ^^^^^^^^^^^^^^^^^^ %{msg}
      x = 1
    RUBY
  end

  it "=begin と =end の間に語があれば落とす" do
    expect_offense(<<~RUBY, msg: message("TODO"))
      =begin
      ^^^^^^ %{msg}
      TODO: あとで消す
      =end
      x = 1
    RUBY
  end

  it "文字列とヒアドキュメントの中の # と、マジックコメントは通す" do
    expect_no_offenses(<<~'RUBY')
      # frozen_string_literal: true
      a = "# TODO: M15 で足す"
      b = 'レビューで直した # FIXME'
      c = <<~TEXT
        # TODO: 以前は M3 だった
      TEXT
    RUBY
  end

  it "guides/comments.md の良い例と、語に似た文字列を通す" do
    expect_no_offenses(<<~RUBY)
      # role IN (...) と書くと、structure.sql を読み込み直したときに式の表記が変わり、差分検査が落ちる
      t.check_constraint "role::text IN ('admin', 'member')", name: "users_role_check"
      # graphql-ruby は FORBIDDEN などの GraphQL::ExecutionError を拾って errors に載せるので、例外としては届かない
      raise ActiveRecord::Rollback if result["errors"].present?
      # 投入の時機を基底クラスに明示する。Rails の更新で既定値が変わっても黙って切り替わらない（docs/adr/005 決定 2）
      self.enqueue_after_transaction_commit = true
      # 受注側が所有する出荷実績。発注側が経路 3 で読む SupplierShipment とは別の型にする
      #   （docs/architecture/graphql-schema.md「視点ごとに型を分ける」）
      # M2M の関連、PM10 の値、TODOS の列、XOI-1 の型番は、番号でも予定でも台帳の ID でもない
      label = "M14 は文字列なので止めない"
    RUBY
  end
end
