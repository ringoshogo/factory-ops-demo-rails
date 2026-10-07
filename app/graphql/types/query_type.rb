module Types
  class QueryType < BaseObject
    field :viewer, ViewerType, null: false

    def viewer
      Current.actor
    end
  end
end
