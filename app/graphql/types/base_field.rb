module Types
  class BaseField < GraphQL::Schema::Field
    connection_extension Connections::ForwardConnectionExtension
  end
end
