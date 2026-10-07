module Mutations
  # 公開した品目は、view_catalog の付与がある取引先のカタログ（経路 1）に現れる
  class SetItemPublished < BaseMutation
    perspective :supplier
    authorize_with Sales::ItemPolicy, :manage?

    argument :item_id, ID
    argument :published, Boolean
    result_field :item, Types::ItemType

    # 自社の品目だけを引く。見えない ID は NOT_FOUND になる
    def find_target(item_id:, **)
      Sales::Catalog.item(current_user, item_id)
    end

    def perform(target, published:, **)
      Sales::Catalog.set_published(current_user, item_id: target.id, published:)
    end
  end
end
