module Sales
  # 販売単価の 1 行（docs/adr/006）。行は書き換えず、現在の行（記録期間が終わっていない行）を閉じて新しい行を足す。
  # 閉じる以外の UPDATE と DELETE はトリガーが拒むので、行の変更は close! と add! だけで行う。
  # 範囲の型は、上限なしの日付を ±Infinity で、上限なしの時刻を nil で読むので、端は valid_from などで読む
  class ItemPrice < TenantRecord
    belongs_to :item

    attribute :recorded_period, RecordedPeriodType.new

    # 上限は列の型（bigint）の最大値。超えた値は保存の時点で ActiveModel::RangeError になり、ユーザーエラーに写らない
    BIGINT_MAX = 9_223_372_036_854_775_807
    validates :unit_price, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: BIGINT_MAX }

    # 記録期間が終わっていない行。パッケージの外からは、記録期間の条件を書き忘れないよう公開 API の price_at を通す
    scope :current, -> { where("upper_inf(item_prices.recorded_period)") }
    # as_of の時点で正しいと信じていた行。空ならいま信じている行
    scope :believed_at, ->(as_of) { as_of ? where("item_prices.recorded_period @> ?::timestamptz", as_of) : current }
    scope :valid_on, ->(date) { where("item_prices.valid_period @> ?::date", date) }
    scope :in_valid_order, -> { order(Arel.sql("lower(item_prices.valid_period) ASC NULLS FIRST")) }

    # 単価の有効日の今日。ACL が受注日に使う日付と同じにし、カタログで見た単価と、同じ時点の発注の受注明細の単価を揃える
    # （docs/adr/006 決定 6）
    def self.today = Date.current

    # 行の集まりから、有効日を含む行の単価を選ぶ。品目は同じ記録時点では有効期間が重ならないので、高々 1 行に当たる
    def self.price_on(rows, date) = rows&.find { _1.covers?(date) }&.unit_price

    # 現在の行として足す。記録の時刻 at は、同じ操作で閉じる行と同じ値を渡し、記録期間を隙間なく接する
    def self.add!(item_id:, unit_price:, valid_from:, valid_to:, at:, reason: nil, recorded_by_user_id: nil)
      create!(owner_tenant_id: Current.tenant_id, item_id:, unit_price:, valid_period: valid_from...valid_to,
        recorded_period: at..., reason:, recorded_by_user_id:)
    end

    def valid_from = finite(valid_period.begin)
    def valid_to = finite(valid_period.end)
    def recorded_from = recorded_period.begin
    def recorded_to = recorded_period.end

    def covers?(date) = (valid_from.nil? || valid_from <= date) && (valid_to.nil? || date < valid_to)

    # 記録期間の上限を at にする。ほかの接続が先に閉じた行なら、書き換えずに例外にする
    def close!(at)
      closed = self.class.current.where(id:).update_all([ "recorded_period = tstzrange(lower(recorded_period), ?)", at ])
      raise ActiveRecord::StaleObjectError.new(self, "close") unless closed == 1
    end

    private

    def finite(bound) = bound.is_a?(Float) ? nil : bound
  end
end
