module Imports
  # 取り込みの開始・読み取り・再登録（docs/architecture/graphql-schema.md「読み取りの一覧」「mutation の一覧」）
  module Runs
    # 取り込みの依頼。自社の置いたファイルでなければ nil で、mutation が NOT_FOUND にする
    def self.request(actor, file_id:, kind:)
      file = Scope.call(actor, ImportFile.where(id: file_id)).first or return
      ImportRequestValue.new(file_id: file.id, owner_tenant_id: file.owner_tenant_id, kind:)
    end

    # 取り込みの行を書き、コミットの後にジョブを登録する（docs/adr/007 決定 5 の A-4）。ジョブを失っても、取り込みは
    # 待機中のまま画面に残り、運用者が reenqueue で拾い直せる。同じファイルの 2 回目は CONFLICT にする
    def self.start(actor, request)
      import = Import.transaction(requires_new: true) do
        Import.create!(owner_tenant_id: actor.tenant_id, import_file_id: request.file_id, kind: request.kind,
          requested_by_user_id: actor.user_id)
      end
      RunJob.perform_later(import.id, import.owner_tenant_id)
      OperationResult.success(to_value(import))
    rescue ActiveRecord::RecordNotUnique
      OperationResult.failure(:conflict, path: [ :file_id ], message: "This file has already been imported")
    end

    def self.list(actor, first:, after:)
      Page.of(Scope.call(actor, Import.all), first:, after:) { |imports| imports.map { to_value(_1) } }
    end

    # 見えない ID は存在しない ID と同じく nil になる
    def self.find(actor, id)
      Scope.call(actor, Import.where(id:)).first&.then { to_value(_1) }
    end

    # 失敗した行を行番号の順に返す。見えない取り込みの ID は空になる
    def self.row_errors(actor, import_id, first:, after:)
      raise Page::InvalidCursor, "invalid cursor" if after && !after.match?(/\A\d+\z/)

      relation = Scope.call(actor, ImportRow.failed.where(import_id:))
      Page.of(relation, first:, after: after&.to_i, key: :row_number, direction: :asc) do |rows|
        rows.map { ImportRowErrorValue.new(row_number: _1.row_number, message: _1.error) }
      end
    end

    # ジョブを失って終わっていない取り込みに、新しいジョブを登録する（rake タスク imports:reenqueue）。
    # 動いているジョブがあっても、新しいジョブはテナントの上限で待ち、置き場の結果のある行を飛ばすので結果は変わらない。
    # 終えた取り込みと見えない取り込みには登録せず、偽を返す
    def self.reenqueue(import_id)
      Tenancy.require_tenant!
      import = Import.find_by(id: import_id)
      return false if import.nil? || import.done?

      RunJob.perform_later(import.id, import.owner_tenant_id)
      true
    end

    def self.to_value(import)
      ImportValue.new(**import.slice(*(ImportValue.members - [ :status ]).map(&:to_s)).symbolize_keys, status: import.status)
    end
    private_class_method :to_value
  end
end
