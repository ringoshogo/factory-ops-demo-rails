module Connections
  # 一覧のリゾルバが返す値。ブロックは件数とカーソルを受け取り、公開 API を呼んで Page を返す。
  # 件数は PagedConnection が上限で丸めてから渡す
  class PagedQuery
    def initialize(&fetch)
      @fetch = fetch
    end

    def call(first:, after:) = @fetch.call(first:, after:)
  end
end
