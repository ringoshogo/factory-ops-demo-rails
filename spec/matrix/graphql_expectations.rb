# 入口の行列の期待値。視点の入口と Mutation のフィールドはすべてここに行を持つ。
# 行の無いフィールドがあれば spec/matrix/graphql_matrix_spec.rb が落ちる
module MatrixExpectations
  # 値が返る・空の一覧・null・ユーザーエラーの NOT_FOUND と NOT_PERMITTED・トップレベルのエラーの FORBIDDEN
  # （docs/architecture/graphql-schema.md「エラー」）
  OUTCOMES = %i[value empty null not_found not_permitted forbidden].freeze

  # "型.フィールド" => { query:, variables: ->(world) { ... }（省略可）, expect: { ペルソナ => 結果 } }。
  # query は対象のフィールドを 1 つだけ選ぶ。variables は世界の行の ID を引数に渡すときに書く
  # 世界の各ペルソナは、自社が受注側の取引関係を factory で 1 件ずつ持つ（相手は世界の外のテナント）
  EVERYONE = MatrixWorld::PERSONAS.index_with(:value).freeze
  # supplier の行を対象にする mutation。相手のペルソナからは見えない ID なので NOT_FOUND になる
  ONLY_SUPPLIER = MatrixWorld::PERSONAS.index_with(:not_found).merge(supplier: :value).freeze

  PARTNERSHIP_MUTATION = "{ partnership { id } errors { code } }".freeze
  ITEM_MUTATION = "{ item { id } errors { code } }".freeze

  GRAPHQL = {
    "Query.viewer" => {
      query: "{ viewer { id } }",
      expect: EVERYONE
    },
    "SupplierView.partnerships" => {
      query: "{ supplier { partnerships { id } } }",
      expect: EVERYONE
    },
    # 経路 2。有効な取引関係があれば権限付与が無くても開き、失効で閉じる
    "BuyerView.suppliers" => {
      query: "{ buyer { suppliers { supplier { name } } } }",
      expect: { supplier: :empty, granted_buyer: :value, ungranted_buyer: :value, revoked_buyer: :empty, stranger: :empty }
    },
    "SupplierView.items" => {
      query: "{ supplier { items { nodes { id } } } }",
      expect: EVERYONE
    },
    # 経路 1。有効な取引関係と view_catalog の付与がある発注側にだけ開き、付与があっても失効で閉じる
    "SupplierPartnership.catalog" => {
      query: "{ buyer { suppliers { catalog { nodes { code } } } } }",
      expect: { supplier: :empty, granted_buyer: :value, ungranted_buyer: :empty, revoked_buyer: :empty, stranger: :empty }
    },
    "Mutation.establishPartnership" => {
      query: "mutation($input: EstablishPartnershipInput!) { establishPartnership(input: $input) #{PARTNERSHIP_MUTATION} }",
      # 世界の外の新しいテナントと結ぶ。create_tenant は取引用コードを "p-<code>" にする
      variables: ->(world) { world.create_tenant("newcomer") && { input: { partnerCode: "p-newcomer" } } },
      expect: EVERYONE
    },
    "Mutation.revokePartnership" => {
      query: "mutation($input: RevokePartnershipInput!) { revokePartnership(input: $input) #{PARTNERSHIP_MUTATION} }",
      variables: ->(world) { { input: { partnershipId: world.partnership(:granted_buyer).id } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.grantPermission" => {
      query: "mutation($input: GrantPermissionInput!) { grantPermission(input: $input) #{PARTNERSHIP_MUTATION} }",
      variables: ->(world) { { input: { partnershipId: world.partnership(:ungranted_buyer).id, permission: "VIEW_CATALOG" } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.withdrawPermission" => {
      query: "mutation($input: WithdrawPermissionInput!) { withdrawPermission(input: $input) #{PARTNERSHIP_MUTATION} }",
      variables: ->(world) { { input: { partnershipId: world.partnership(:granted_buyer).id, permission: "VIEW_CATALOG" } } },
      expect: ONLY_SUPPLIER
    },
    "Mutation.saveItem" => {
      query: "mutation($input: SaveItemInput!) { saveItem(input: $input) #{ITEM_MUTATION} }",
      variables: ->(_world) { { input: { code: "NEW-1", name: "新しい品目", unit: "個", unitPrice: 100 } } },
      expect: EVERYONE
    },
    "Mutation.setItemPublished" => {
      query: "mutation($input: SetItemPublishedInput!) { setItemPublished(input: $input) #{ITEM_MUTATION} }",
      variables: ->(world) { { input: { itemId: world.row("items", :supplier).id, published: true } } },
      expect: ONLY_SUPPLIER
    }
  }.freeze
end
