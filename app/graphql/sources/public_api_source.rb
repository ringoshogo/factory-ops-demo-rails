module Sources
  # 入れ子のフィールドから、公開 API の一括取得のメソッドを親の ID をまとめて 1 回だけ呼ぶ
  # （docs/architecture/graphql-schema.md「ページングと N+1」）。メソッドは操作者と ID の配列を取り、ID ごとの値のハッシュを返す。
  # キーワード引数（記録時点など）は、同じ値を渡したフィールドどうしだけをまとめる
  class PublicApiSource < GraphQL::Dataloader::Source
    def initialize(api, method, actor, **options)
      @api = api
      @method = method
      @actor = actor
      @options = options
    end

    def fetch(ids)
      values = @api.public_send(@method, @actor, ids, **@options)
      ids.map { values[_1] }
    end
  end
end
