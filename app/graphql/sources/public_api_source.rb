module Sources
  # 入れ子のフィールドから、公開 API の一括取得のメソッドを親の ID をまとめて 1 回だけ呼ぶ
  # （docs/architecture/graphql-schema.md「ページングと N+1」）。メソッドは操作者と ID の配列を取り、ID ごとの値のハッシュを返す
  class PublicApiSource < GraphQL::Dataloader::Source
    def initialize(api, method, actor)
      @api = api
      @method = method
      @actor = actor
    end

    def fetch(ids)
      values = @api.public_send(@method, @actor, ids)
      ids.map { values[_1] }
    end
  end
end
