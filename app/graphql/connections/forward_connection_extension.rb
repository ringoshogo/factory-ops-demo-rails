module Connections
  # 一覧の引数を first・after だけにする。既定の拡張が足す last・before は、公開 API が前へ辿らないので置かない
  class ForwardConnectionExtension < GraphQL::Schema::Field::ConnectionExtension
    def apply
      field.argument :first, "Int", required: false
      field.argument :after, "String", required: false
    end
  end
end
