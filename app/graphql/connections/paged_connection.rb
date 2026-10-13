module Connections
  # 公開 API が返す Page をコネクションに包む（docs/architecture/graphql-schema.md「ページングと N+1」）。
  # 前へは辿らない。カーソルは公開 API が決めた値をそのまま使う
  class PagedConnection < GraphQL::Pagination::Connection
    def nodes = page.values

    def has_next_page = page.has_next_page

    def has_previous_page = false

    def cursor_for(node) = page.cursors.fetch(nodes.index(node))

    def total_count = page.total_count

    private

    def page
      @page ||= items.call(first:, after:)
    rescue Page::InvalidCursor
      raise GraphQL::ExecutionError, "Invalid cursor"
    end
  end
end
