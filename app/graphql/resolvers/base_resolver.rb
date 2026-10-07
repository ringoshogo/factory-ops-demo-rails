module Resolvers
  # buyer・supplier の入口の下のフィールドは、すべてこのクラスから作る。
  # perspective と authorize_with <Policy>, :<規則> を宣言し、解決の前に操作者に対して規則を評価する
  class BaseResolver < GraphQL::Schema::Resolver
    include ActionPolicy::GraphQL::Behaviour
    include AuthorizationDeclarations

    def authorized?(**args)
      self.class.check_declarations!
      super && enforce_rule!(current_user)
    end
  end
end
