module RuboCop
  module Cop
    module FactoryOps
      # コメントに、開発の経緯・マイルストーンの番号・台帳の ID・予定を書かせない（docs/guides/comments.md「機械で止めるもの」）。
      # 語の一覧を変えるときは、guides/comments.md「機械で止めるもの」も同じ変更で直す。
      # 語でしか判定しないので、規則に沿った文が止まったら、Cop を無効にせず文を言い換える。
      # 番号と予定の語の前後は ASCII の英数字だけを語の続きとみなす。
      # Ruby の \b は日本語の文字も語の文字に数えるので、\b で区切ると日本語に続けて書いた番号を見逃す。
      # 「直す」の過去形は助詞の「を」から見る。「読み込み直す」のような複合動詞の過去形を止めないためである。
      # 止める例は、このコメント自体が止まらないように spec に置く。
      #
      # @example
      #   # good
      #   # 発注側が経路 3 で読む SupplierShipment とは別の型にする（docs/architecture/graphql-schema.md「視点ごとに型を分ける」）
      class NoHistoryComment < Base
        MSG = "コメントに経緯・マイルストーンの番号・台帳の ID・予定を書かない（%<term>s）。いまの振る舞いと理由だけを書く（docs/guides/comments.md）。"

        WORD_BEFORE = "(?<![A-Za-z0-9_])"
        WORD_AFTER = "(?![A-Za-z0-9_])"
        MILESTONE = /#{WORD_BEFORE}M\d+#{WORD_AFTER}/
        LEDGER_ID = /#{WORD_BEFORE}(?:OI|IB)-\d+#{WORD_AFTER}/
        HISTORY_WORDS = %w[以前は レビューで 指摘で を直した 当初は].freeze
        PLAN_WORDS = /#{WORD_BEFORE}(?:TODO|FIXME)#{WORD_AFTER}/
        PATTERN = Regexp.union(MILESTONE, LEDGER_ID, *HISTORY_WORDS, PLAN_WORDS)

        def on_new_investigation
          processed_source.comments.each do |comment|
            term = comment.text[PATTERN]
            add_offense(comment, message: format(MSG, term: term)) if term
          end
        end
      end
    end
  end
end
