# 規則による拒否・宣言漏れ・scope と規則の食い違いを、どこで起きても同じトップレベルのエラーにする
class ForbiddenError < GraphQL::ExecutionError
  def initialize(message = "Forbidden")
    super(message, extensions: { "code" => "FORBIDDEN" })
  end
end
