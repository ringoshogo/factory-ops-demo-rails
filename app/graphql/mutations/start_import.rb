module Mutations
  # 置いたファイルの取り込みを始め、ジョブを登録する。業務の表に効果が及ぶのはここからなので、ここで監査する。
  # 規則は取り込みの依頼（ファイルと種類）に対して評価し、品目の CSV は単価の列を含むので admin に限る
  # （docs/architecture/graphql-schema.md「役割による制限」）。見えないファイルは NOT_FOUND、同じファイルの 2 回目は CONFLICT
  class StartImport < BaseMutation
    perspective :supplier
    authorize_with Imports::ImportPolicy, :start?
    audit "import.start", target: ->(result:, **) { result }, counterparty: nil

    argument :file_id, ID
    argument :kind, Types::ImportKindType
    result_field :import, Types::ImportType

    def find_target(file_id:, kind:)
      Imports::Runs.request(current_user, file_id:, kind:)
    end

    def perform(target, **)
      Imports::Runs.start(current_user, target)
    end
  end
end
