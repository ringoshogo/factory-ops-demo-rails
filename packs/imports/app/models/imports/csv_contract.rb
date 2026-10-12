module Imports
  # 取り込みの CSV の見出しと、行ごとの検証（docs/architecture/data-model.md「取り込み（`imports`）」）。
  # 行の検証は、値の形と範囲だけを見る。同じファイルの同じコードと、自社の品目にあるかは、反映のときに置き場と公開 API で確かめる。
  # 誤りの文は GraphQL のユーザーエラーと同じく英語で、「列名: 理由」の形にする
  module CsvContract
    COLUMNS = CsvFormat::COLUMNS
    # 単価は bigint、数量は integer の列に入る
    MAX_UNIT_PRICE = 2**63 - 1
    MAX_QUANTITY = 2**31 - 1
    NON_NEGATIVE_INTEGER = /\A\d+\z/
    DATE = /\A\d{4}-\d{2}-\d{2}\z/

    Invalid = Class.new(StandardError)

    def self.header?(kind, header) = header == COLUMNS.fetch(kind)

    # 値の配列を、列名を鍵にした値にする。外れた列があれば、最初の列の誤りの文で Invalid を投げる
    def self.parse(kind, values)
      columns = COLUMNS.fetch(kind)
      raise Invalid, "row has #{values.size} columns, expected #{columns.size}" unless values.size == columns.size

      row = columns.zip(values.map { _1.to_s.strip }).to_h
      kind == "items" ? parse_item(row) : parse_stock(row)
    end

    def self.parse_item(row)
      %w[code name unit].each { |column| invalid!(column, "can't be blank") if row[column].empty? }
      { code: row["code"], name: row["name"], unit: row["unit"],
        tax_rate_percent: { "8" => 8, "10" => 10 }.fetch(row["tax_rate_percent"]) { invalid!("tax_rate_percent", "must be 8 or 10") },
        published: { "true" => true, "false" => false }.fetch(row["published"]) { invalid!("published", "must be true or false") },
        unit_price: row["unit_price"].empty? ? nil : integer!(row, "unit_price", MAX_UNIT_PRICE),
        price_effective_on: row["price_effective_on"].empty? ? nil : effective_on!(row["price_effective_on"]) }
    end

    def self.parse_stock(row)
      invalid!("item_code", "can't be blank") if row["item_code"].empty?
      { item_code: row["item_code"], quantity: integer!(row, "quantity", MAX_QUANTITY) }
    end

    def self.integer!(row, column, max)
      value = row[column]
      invalid!(column, "must be an integer between 0 and #{max}") unless value.match?(NON_NEGATIVE_INTEGER) && value.to_i <= max
      value.to_i
    end

    # 改定日は今日以降。単価の改定の予約（Sales::ItemPrices.schedule）と同じ規則にする
    def self.effective_on!(value)
      date = (Date.iso8601(value) if value.match?(DATE)) or invalid!("price_effective_on", "must be a date in YYYY-MM-DD")
      invalid!("price_effective_on", "must be today or later") if date < Date.current
      date
    rescue Date::Error
      invalid!("price_effective_on", "must be a date in YYYY-MM-DD")
    end

    def self.invalid!(column, reason) = raise(Invalid, "#{column}: #{reason}")

    private_class_method :parse_item, :parse_stock, :integer!, :effective_on!, :invalid!
  end
end
