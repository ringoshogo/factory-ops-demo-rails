module Mutations
  # 取引先の得意先品番に自社の品目を対応させる。照合待ちの受注は照合し直し、全明細が照合できれば確定する。
  # 見えない品目と、自社が受注側の取引関係に無い取引先は NOT_FOUND
  class RegisterPartMapping < BaseMutation
    perspective :supplier
    authorize_with Sales::PartMappingPolicy, :register?

    argument :customer_tenant_id, ID
    argument :customer_part_number, String
    argument :item_id, ID
    result_field :part_mapping, Types::PartMappingType

    def perform(**input)
      Sales::PartMappings.register(current_user, **input)
    end
  end
end
