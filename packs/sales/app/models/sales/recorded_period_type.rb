require "active_record/connection_adapters/postgresql_adapter"

module Sales
  # 販売単価の記録期間（tstzrange）の型。終わりの無い範囲を "[始まり,)" で書き、終わりを持たない範囲にする。
  # activerecord 8.1 は、始まりが Time の終わりの無い日時の範囲の終わりを infinity で書く（postgresql/quoting.rb の encode_range）。
  # infinity の終わりは upper_inf が偽なので、その行は現在の行に数えられず、足す行を確かめるトリガーにも拒まれる。
  # アプリの時刻帯が UTC でないと、始まりの時刻は直列化で Time に変わり（activemodel の Helpers::TimeValue#serialize_cast_value）、
  # この形になる（docs/adr/006 決定 3）
  class RecordedPeriodType < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Range
    def initialize
      super(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::TimestampWithTimeZone.new, :tstzrange)
    end

    def serialize(value)
      return super unless value.is_a?(::Range) && value.end.nil? && !value.begin.nil?

      "[#{@subtype.cast(value.begin).utc.iso8601(6)},)"
    end
  end
end
