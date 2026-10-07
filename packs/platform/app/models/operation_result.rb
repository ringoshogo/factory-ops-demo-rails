# 公開 API の操作が返す結果。業務の不変条件の違反は例外にせず、失敗の結果で返す。
# GraphQL の基底 mutation が、失敗をユーザーエラーに写す（docs/architecture/graphql-schema.md「エラー」）
class OperationResult
  CODES = %i[invalid_input not_found not_permitted conflict].freeze

  # path は原因の入力項目（例：[:lines, 0, :quantity]）。入力全体なら nil
  Failure = Data.define(:code, :path, :message)

  attr_reader :value, :failures

  def self.success(value = nil)
    new(value:, failures: [])
  end

  def self.failure(code, path: nil, message: nil)
    raise ArgumentError, "unknown code: #{code}" unless CODES.include?(code)

    new(value: nil, failures: [ Failure.new(code:, path:, message:) ])
  end

  def initialize(value:, failures:)
    @value = value
    @failures = failures
  end

  def success?
    failures.empty?
  end
end
