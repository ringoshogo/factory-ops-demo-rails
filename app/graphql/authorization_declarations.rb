# 型・リゾルバ・mutation が宣言する視点と認可（docs/architecture/graphql-schema.md「基底クラス」）。
# 宣言はクラスごとに書かせ、親クラスから引き継がない
module AuthorizationDeclarations
  extend ActiveSupport::Concern

  # root は Query と Mutation だけが使う
  PERSPECTIVES = %i[buyer supplier shared root].freeze

  class MissingDeclaration < StandardError; end

  class_methods do
    def perspective(value = nil)
      return @perspective if value.nil?
      raise ArgumentError, "unknown perspective: #{value}" unless PERSPECTIVES.include?(value)

      @perspective = value
    end

    def authorize_with(policy, rule)
      @authorization_policy = policy
      @authorization_rule = rule
    end

    def authorization_policy = @authorization_policy
    def authorization_rule = @authorization_rule

    def authorization_declared?
      authorization_policy.present?
    end

    # 宣言が無ければ、開発とテストでは例外で落とし、本番では拒否してエラー通知に送る
    def check_declarations!(context)
      missing = missing_declarations
      return if missing.empty?

      error = MissingDeclaration.new("#{graphql_name} lacks #{missing.join(' and ')} declaration")
      raise error if Rails.env.local?

      Rails.error.report(error)
      raise ForbiddenError.new(context, reason: "undeclared")
    end

    # 欠けている宣言の名前。宣言を足す基底クラスは、これを広げる
    def missing_declarations
      [ ("perspective" unless perspective), ("authorization" unless authorization_declared?) ].compact
    end
  end

  private

  # リゾルバと mutation の規則の評価。拒否は偽を返さず FORBIDDEN を投げる
  def enforce_rule!(record)
    return true if allowed_to?(self.class.authorization_rule, record, with: self.class.authorization_policy)

    raise ForbiddenError.new(context, reason: "rule")
  end
end
