module Contracts
  # イベントの型。ID と、受け手が要る値の写しだけを持つ値オブジェクトにし、発行元のモデルは運ばない。
  #   OrderPlaced = Contracts::Event.define(:purchase_order_id, :supplier_tenant_id, :lines)
  module Event
    PRIMITIVES = [ String, Integer, TrueClass, FalseClass, NilClass ].freeze

    def self.define(*members)
      Data.define(*members).tap do |klass|
        klass.include(self)
        klass.extend(ClassMethods)
      end
    end

    module ClassMethods
      def from_payload(payload)
        new(**payload.symbolize_keys)
      end
    end

    # ジョブの引数に載せるハッシュ。キーを文字列に揃え、プリミティブ以外を拒む。
    # 日付や金額は文字列にして載せる。ジョブの直列化に任せると、受け手が受け取る型が発行元の型に縛られる
    def to_payload
      to_h.deep_stringify_keys.tap { |payload| Event.assert_primitive!(payload) }
    end

    def self.assert_primitive!(value)
      case value
      when Hash then value.each_value { |v| assert_primitive!(v) }
      when Array then value.each { |v| assert_primitive!(v) }
      when *PRIMITIVES then nil
      else raise ArgumentError, "イベントはプリミティブだけを運ぶ: #{value.class}"
      end
    end
  end
end
