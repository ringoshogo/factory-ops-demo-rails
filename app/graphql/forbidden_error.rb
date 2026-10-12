# 規則による拒否・宣言漏れ・scope と規則の食い違いを、どこで起きても同じトップレベルのエラーにする。
# 出どころは応答に載せず、エラーに持たせる。操作の終わりのイベントが、応答に載ったエラーから集めてメトリクスに運ぶ
# （docs/architecture/graphql-schema.md「エラー」）
class ForbiddenError < GraphQL::ExecutionError
  # rule は操作の規則（役割を含む）、object は返すオブジェクトとフィールドの規則、undeclared は宣言の無い型・リゾルバ・mutation
  REASONS = %w[rule object undeclared].freeze

  attr_reader :reason

  def initialize(reason:)
    raise ArgumentError, "unknown reason: #{reason}" unless REASONS.include?(reason)

    @reason = reason
    super("Forbidden", extensions: { "code" => "FORBIDDEN" })
  end
end
