module Types
  class PageInfoType < BaseObject
    include GraphQL::Types::Relay::PageInfoBehaviors

    graphql_name "PageInfo"
    perspective :shared
    authorization_exempt reason: "データを持たない"
  end
end
