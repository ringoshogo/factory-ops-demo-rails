# 規則による拒否・宣言漏れ・scope と規則の食い違いを、どこで起きても同じトップレベルのエラーにする。
# 出どころは応答に載せず、要求の文脈に積む。操作の終わりのイベントが、メトリクスの FORBIDDEN の内訳に運ぶ
# （docs/architecture/graphql-schema.md「エラー」）
class ForbiddenError < GraphQL::ExecutionError
  # rule は操作の規則（役割を含む）、object は返すオブジェクトとフィールドの規則、undeclared は宣言の無い型・リゾルバ・mutation
  REASONS = %w[rule object undeclared].freeze

  # 作るときに積む。積むのを呼び出し元に任せると、FORBIDDEN の数と出どころの数が食い違い、内訳が数えられない
  def initialize(context, reason:)
    raise ArgumentError, "unknown reason: #{reason}" unless REASONS.include?(reason)

    (context[:forbidden_reasons] ||= []) << reason
    super("Forbidden", extensions: { "code" => "FORBIDDEN" })
  end
end
