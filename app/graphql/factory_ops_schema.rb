class FactoryOpsSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType
  # extra_types で型を足さない。graphql-ruby 2.6 の書き出しが同じ型を schema.graphql に 2 回書く。共通の型はフィールドから届かせる
  # （docs/architecture/graphql-schema.md「スキーマの変更と非推奨」）

  # ソースはリクエストのトランザクションと同じ接続で動かす。AsyncDataloader は使わない
  # （docs/architecture/graphql-schema.md「ページングと N+1」）
  use GraphQL::Dataloader

  # 一覧のリゾルバは公開 API を呼ぶ PagedQuery を返し、公開 API が返す Page をコネクションに包む
  connections.add(Connections::PagedQuery, Connections::PagedConnection)

  max_depth 10
  max_complexity 2_500
  default_page_size 20
  default_max_page_size 100

  class << self
    # ID から型を問わずにレコードを引く入口を作らない。node と引数の loads: が使えなくなる（adr/004）
    def object_from_id(_id, _context)
      raise NotImplementedError, "object_from_id is intentionally not implemented (adr/004)"
    end

    # graphql-ruby は authorized? が偽なら値を null にするだけなので、FORBIDDEN のエラーにする
    def unauthorized_object(error)
      Rails.error.report(error)
      raise ForbiddenError
    end

    def unauthorized_field(error)
      Rails.error.report(error)
      raise ForbiddenError
    end
  end
end
