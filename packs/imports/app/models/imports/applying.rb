module Imports
  # 反映する段階（docs/adr/007 決定 5 の A-4、docs/architecture/data-model.md「取り込み（`imports`）」）。
  # 結果の無い行を行番号の順にチャンクで取り、業務の書き込み・行の結果・件数の加算をチャンクの 1 つのトランザクションで書く。
  # 結果のある行は取らないので、同じチャンクをもう一度流しても、業務の行も件数も増えない
  module Applying
    CHUNK_ROWS = 500
    # 在庫の移動履歴の理由
    STOCK_REASON = "CSV の取り込み".freeze

    # 1 チャンクを反映し、その最後の行番号を返す。結果の無い行が無いか、取り込みを終えていれば nil を返す。
    # 取り込みを始めたユーザーが、いまも開始の規則を満たすかをチャンクごとに確かめ、満たさなければ取り込み全体を失敗にする。
    # 品目の CSV は単価を変えるので、admin でなくなったユーザーの名義で単価を変え続けない
    def self.next_chunk(import_id, tenant_id)
      Chunk.locked(import_id, tenant_id) do |import|
        actor = Partnerships::Authentication.acting_user(import.requested_by_user_id)
        request = ImportRequestValue.new(file_id: import.import_file_id, owner_tenant_id: import.owner_tenant_id, kind: import.kind)
        unless actor && ImportPolicy.new(request, user: actor).apply(:start?)
          Chunk.fail!(import, "not_permitted")
          next
        end

        rows = ImportRow.pending.where(import_id:).order(:row_number).limit(CHUNK_ROWS).to_a
        next if rows.empty?

        errors = import.kind == "items" ? apply_items(actor, import, rows) : apply_stocks(actor, import, rows)
        record(import, rows, errors)
        rows.last.row_number
      end
    end

    # 品目の列は Sales::Catalog.bulk_upsert でチャンクごとに 1 回で書き、新しい品目は最初の単価を持つ。
    # 既存の品目の単価の列は、単価の改定の予約（Sales::ItemPrices.schedule）で反映し、品目の登録からは変えない。
    # 改定日の単価をチャンクごとにまとめて引き、違う行だけを予約する。作ったばかりの品目と、もう一度流した行は単価が同じなので、
    # 予約を呼ばない。失敗した行は書き込みに含めないので、戻す書き込みが無い
    def self.apply_items(actor, import, rows)
      parsed, errors = parse(import, rows)
      results = Sales::Catalog.bulk_upsert(actor, parsed.values.map { _1.except(:price_effective_on) })
      changes = parsed.filter_map do |row, attributes|
        result = results.fetch(attributes[:code])
        unless result.success?
          errors[row] = message(result)
          next
        end
        next if attributes[:unit_price].nil?

        { item_id: result.value.item_id, unit_price: attributes[:unit_price], effective_on: attributes[:price_effective_on] || Date.current }
      end
      changes.group_by { _1[:effective_on] }.each do |effective_on, group|
        prices = Sales::ItemPrices.price_at(actor, group.map { _1[:item_id] }, valid_on: effective_on)
        group.reject { prices[_1[:item_id]] == _1[:unit_price] }.each { schedule!(actor, **_1) }
      end
      errors
    end

    # 改定日と単価は検証を通り、品目は単価の行を持つので、失敗は日付が変わった瞬間か不変条件の崩れである。
    # 品目の列を書いた後なので、行の失敗にせず例外でチャンクごと戻す。その実行で段階かカーソルを進めていれば、Continuable が
    # 続きから登録し直し、検証からやり直す（activejob 8.1.4 の resume_errors_after_advancing の既定は真）。進めていなければ
    # 失敗したジョブになり、運用者が imports:reenqueue で登録し直す
    def self.schedule!(actor, item_id:, unit_price:, effective_on:)
      scheduled = Sales::ItemPrices.schedule(actor, item_id:, unit_price:, effective_on:)
      raise "単価の改定の予約に失敗した（#{message(scheduled)}）" unless scheduled.success?
    end

    # 在庫は品目 ID の昇順に、行ごとのセーブポイントで目標の数量に合わせる。並んだ取り込みと引当が、在庫の行を同じ順でロックする。
    # 品目コードから ID を引くのは受注の公開 API で、自社の品目であることの保証は在庫数の設定（Inventory::Adjustment.set_quantity）が持つ。
    # 写しは品目と同じトランザクションで書く（docs/adr/011 決定 1）。写しを書く経路の抜けと、写しの表を足した後の既存の DB は
    # read_models:rebuild が埋めるまで写しが無く、その行は在庫数の設定が NOT_FOUND で拒む
    def self.apply_stocks(actor, import, rows)
      parsed, errors = parse(import, rows)
      item_ids = Sales::Catalog.ids_by_codes(actor, parsed.values.map { _1[:item_code] })
      found, missing = parsed.partition { |_row, attributes| item_ids.key?(attributes[:item_code]) }
      missing.each { |row, _| errors[row] = "item_code: no item with this code" }
      found.sort_by { |_row, attributes| item_ids.fetch(attributes[:item_code]) }.each do |row, attributes|
        result = Inventory::Adjustment.set_quantity(actor, item_id: item_ids.fetch(attributes[:item_code]),
          quantity: attributes[:quantity], reason: STOCK_REASON)
        errors[row] = message(result) unless result.success?
      end
      errors
    end

    # 列の検証と、同じファイルの前の行と同じコードの行を失敗にする。検証を通った行と、行ごとの誤りの文を返す
    def self.parse(import, rows)
      errors = {}
      parsed = rows.each_with_object({}) do |row, values|
        values[row] = CsvContract.parse(import.kind, row.data)
      rescue CsvContract::Invalid => e
        errors[row] = e.message
      end
      first_rows = first_rows_by_code(import, rows)
      column = CsvContract::COLUMNS.fetch(import.kind).first
      parsed.each_key do |row|
        first = first_rows.fetch(row.data.first)
        errors[row] = "#{column}: duplicates row #{first}" if first < row.row_number
      end
      [ parsed.except(*errors.keys), errors ]
    end

    # コードごとの、同じファイルで最初に現れた行番号。前のチャンクの行も含めて置き場から引く
    def self.first_rows_by_code(import, rows)
      ImportRow.where(import_id: import.id).where(row_number: ..rows.last.row_number)
        .where("data->>0 IN (?)", rows.map { _1.data.first }.uniq).group(Arel.sql("data->>0")).minimum(:row_number)
    end

    # 行の結果と件数は、このチャンクで新しく結果を書いた行の数だけ足す
    def self.record(import, rows, errors)
      now = Time.current
      applied = rows.reject { errors.key?(_1) }
      ImportRow.where(id: applied.map(&:id)).update_all(applied_at: now, updated_at: now)
      errors.each { |row, error| ImportRow.where(id: row.id).update_all(error:, updated_at: now) }
      import.update!(applied_rows: import.applied_rows + applied.size, failed_rows: import.failed_rows + errors.size)
      Rails.event.notify("imports.chunk_applied", kind: import.kind, import_id: import.id, applied_rows: applied.size,
        failed_rows: errors.size)
    end

    # 反映で呼ぶ公開 API の失敗は、どれも入力の項目を指す
    def self.message(result)
      failure = result.failures.first
      "#{failure.path.last}: #{failure.message}"
    end

    private_class_method :apply_items, :schedule!, :apply_stocks, :parse, :first_rows_by_code, :record, :message
  end
end
