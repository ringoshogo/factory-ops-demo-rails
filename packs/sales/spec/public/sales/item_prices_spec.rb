require "rails_helper"

# 販売単価の改定の予約と訂正と、有効日と記録時点で引く単価（docs/adr/006 決定 3〜5）。
# 行は書き換えず、現在の行の記録期間を閉じて新しい行を足す。記録の時刻は操作ごとに 1 つで、travel_to で決める
RSpec.describe Sales::ItemPrices do
  include ActiveSupport::Testing::TimeHelpers

  let(:supplier) { FactoryBot.create(:tenant) }
  let(:actor) do
    Partnerships::Actor.new(user_id: SecureRandom.uuid, tenant_id: supplier.id, name: "", email: "", role: "admin", partner_code: "")
  end
  # 品目を作った時刻（t0）、改定を予約した時刻（t1）、訂正した時刻（t2）
  let(:t0) { Time.zone.local(2026, 10, 1, 9) }
  let(:t1) { Time.zone.local(2026, 10, 5, 9) }
  let(:t2) { Time.zone.local(2026, 10, 9, 9) }
  let!(:item) { travel_to(t0) { FactoryBot.create(:item, unit_price: 100) } }
  # 他社の品目・単価の行・照合済みの明細。テナントの入れ子は同じテナントに限るので、自社のテナントに入る前に作る
  let(:foreign) do
    Tenancy.with_tenant(FactoryBot.create(:tenant).id) do
      item = FactoryBot.create(:item, unit_price: 5)
      { item:, price: Sales::ItemPrice.find_by!(item_id: item.id), line: FactoryBot.create(:sales_order_line, :matched) }
    end
  end

  around do |example|
    foreign
    TenantExample.run(example, supplier.id)
  end

  def failures(result) = result.failures.map { [ _1.code, _1.path ] }

  def prices(as_of: nil) = described_class.history(actor, [ item.id ], as_of:).fetch(item.id)

  def price_on(date, as_of: nil) = described_class.price_at(actor, [ item.id ], valid_on: date, as_of:)[item.id]

  describe "予約と訂正を、有効日 × 記録時点で引く" do
    # t1 に 11/1 からの 120 円を予約し、t2 に 11/1 より前の行を 90 円に訂正する
    before do
      travel_to(t1) { expect(described_class.schedule(actor, item_id: item.id, unit_price: 120, effective_on: Date.new(2026, 11, 1))).to be_success }
      corrected = prices.find { _1.valid_to == Date.new(2026, 11, 1) }
      travel_to(t2) do
        expect(described_class.correct(actor, item_price_id: corrected.id, unit_price: 90, reason: "入力の誤り")).to be_success
      end
    end

    {
      "品目を作った後・予約の前" => [ Time.zone.local(2026, 10, 3), { "10/15" => 100, "11/15" => 100 } ],
      "予約の後・訂正の前" => [ Time.zone.local(2026, 10, 7), { "10/15" => 100, "11/15" => 120 } ],
      "訂正の後" => [ Time.zone.local(2026, 10, 10), { "10/15" => 90, "11/15" => 120 } ],
      "いま（記録時点を省く）" => [ nil, { "10/15" => 90, "11/15" => 120 } ]
    }.each do |label, (as_of, expected)|
      it "記録時点が#{label}なら、有効日ごとに #{expected.values.join('・')} 円" do
        actual = expected.keys.index_with { |day| price_on(Date.new(2026, *day.split("/").map(&:to_i)), as_of:) }

        expect(actual).to eq(expected)
      end
    end

    it "記録時点が訂正の時刻ちょうどなら、訂正の後の行だけを信じていた" do
      expect(prices(as_of: t2).map { [ _1.unit_price, _1.recorded_from ] }).to eq([ [ 90, t2 ], [ 120, t1 ] ])
    end

    it "品目を作る前の記録時点では、単価が無い" do
      expect(price_on(Date.new(2026, 10, 15), as_of: Time.zone.local(2026, 9, 30))).to be_nil
    end

    it "いま信じている行を有効期間の順に返し、訂正の行は理由と操作者を持つ" do
      expect(prices.map { [ _1.unit_price, _1.valid_from, _1.valid_to, _1.recorded_from, _1.recorded_to, _1.reason ] }).to eq([
        [ 90, nil, Date.new(2026, 11, 1), t2, nil, "入力の誤り" ],
        [ 120, Date.new(2026, 11, 1), nil, t1, nil, nil ]
      ])
    end

    it "記録時点を渡すと、その時点で信じていた行を返す。閉じた行は記録期間の終わりを持つ" do
      expect(prices(as_of: Time.zone.local(2026, 10, 7)).map { [ _1.unit_price, _1.valid_to, _1.recorded_from, _1.recorded_to ] })
        .to eq([ [ 100, Date.new(2026, 11, 1), t1, t2 ], [ 120, nil, t1, nil ] ])
      expect(prices(as_of: Time.zone.local(2026, 10, 3)).map { [ _1.unit_price, _1.valid_from, _1.recorded_to ] })
        .to eq([ [ 100, nil, t1 ] ])
    end
  end

  describe ".schedule" do
    def schedule(unit_price:, effective_on:, at: t1)
      travel_to(at) { described_class.schedule(actor, item_id: item.id, unit_price:, effective_on:) }
    end

    it "同じ改定日と単価の予約をもう一度流しても、行が増えない" do
      schedule(unit_price: 120, effective_on: Date.new(2026, 11, 1))
      rows = prices

      expect(schedule(unit_price: 120, effective_on: Date.new(2026, 11, 1), at: t2)).to be_success
      expect(prices).to eq(rows)
      expect(described_class.history(actor, [ item.id ], as_of: t2).fetch(item.id).size).to eq(2)
    end

    it "同じ改定日に別の単価を予約し直すと、その日からの行だけを置き換える" do
      schedule(unit_price: 120, effective_on: Date.new(2026, 11, 1))

      expect(schedule(unit_price: 130, effective_on: Date.new(2026, 11, 1), at: t2)).to be_success
      expect(prices.map { [ _1.unit_price, _1.valid_from, _1.valid_to ] })
        .to eq([ [ 100, nil, Date.new(2026, 11, 1) ], [ 130, Date.new(2026, 11, 1), nil ] ])
    end

    it "予約済みの改定より前の日に予約すると、後ろの改定を残して間に行を足す" do
      schedule(unit_price: 120, effective_on: Date.new(2026, 11, 1))

      expect(schedule(unit_price: 110, effective_on: Date.new(2026, 10, 20), at: t2)).to be_success
      expect(prices.map { [ _1.unit_price, _1.valid_from, _1.valid_to ] }).to eq([
        [ 100, nil, Date.new(2026, 10, 20) ], [ 110, Date.new(2026, 10, 20), Date.new(2026, 11, 1) ], [ 120, Date.new(2026, 11, 1), nil ]
      ])
    end

    it "今日と同じ単価の予約は、行を分けない" do
      expect(schedule(unit_price: 100, effective_on: Date.new(2026, 11, 1))).to be_success
      expect(prices.map { [ _1.unit_price, _1.valid_from, _1.valid_to, _1.recorded_from ] }).to eq([ [ 100, nil, nil, t0 ] ])
    end

    it "今日からの改定は、今日のカタログの単価になり、成功の値の品目に写る" do
      result = schedule(unit_price: 150, effective_on: t1.to_date)

      expect(result.value).to have_attributes(id: item.id, unit_price: 150)
      expect(price_on(t1.to_date - 1)).to eq(100)
    end

    it "改定日が今日より前か、単価が負か整数でないか bigint の最大値を超えれば、項目を指す INVALID_INPUT で何も書かない" do
      expect(failures(schedule(unit_price: 120, effective_on: t1.to_date - 1))).to eq([ [ :invalid_input, [ :effective_on ] ] ])
      expect(failures(schedule(unit_price: -1, effective_on: t1.to_date))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
      expect(failures(schedule(unit_price: 1.5, effective_on: t1.to_date))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
      expect(failures(schedule(unit_price: 9_223_372_036_854_775_808, effective_on: t1.to_date)))
        .to eq([ [ :invalid_input, [ :unit_price ] ] ])
      expect(prices.size).to eq(1)
    end

    # 単価の有効日の今日は日本時間で決まる（docs/adr/006 決定 6、docs/architecture/context-map.md「検収と請求の流れ」）
    it "日本時間の 0〜9 時には、日本時間の今日からの改定を受け付け、その前日からの改定を INVALID_INPUT にする" do
      now = Time.utc(2026, 10, 11, 16, 0)

      # 対照：この時刻の UTC の日付は前日である
      expect(now.utc.to_date).to eq(Date.new(2026, 10, 11))
      expect(failures(schedule(unit_price: 120, effective_on: Date.new(2026, 10, 11), at: now))).to eq([ [ :invalid_input, [ :effective_on ] ] ])
      expect(schedule(unit_price: 120, effective_on: Date.new(2026, 10, 12), at: now)).to be_success
    end

    it "単価は bigint の最大値ちょうどまでを受け付ける" do
      expect(schedule(unit_price: 9_223_372_036_854_775_807, effective_on: t1.to_date)).to be_success
      expect(price_on(t1.to_date)).to eq(9_223_372_036_854_775_807)
    end

    it "単価の行が無い品目は CONFLICT、見えない品目は NOT_FOUND" do
      bare = FactoryBot.create(:item, unit_price: nil)

      expect(failures(described_class.schedule(actor, item_id: bare.id, unit_price: 1, effective_on: Date.current)))
        .to eq([ [ :conflict, [ :item_id ] ] ])
      expect(failures(described_class.schedule(actor, item_id: foreign[:item].id, unit_price: 1, effective_on: Date.current)))
        .to eq([ [ :not_found, [ :item_id ] ] ])
    end
  end

  describe ".correct" do
    def correct(row, unit_price: 90, reason: "入力の誤り", at: t2)
      travel_to(at) { described_class.correct(actor, item_price_id: row.id, unit_price:, reason:) }
    end

    it "同じ有効期間で正しい単価の行を足し、操作者を残す" do
      row = prices.sole

      expect(correct(row).value).to have_attributes(id: item.id, unit_price: 90)
      expect(prices.map { [ _1.unit_price, _1.valid_from, _1.valid_to, _1.reason ] }).to eq([ [ 90, nil, nil, "入力の誤り" ] ])
      expect(Sales::ItemPrice.current.sole.recorded_by_user_id).to eq(actor.user_id)
    end

    it "閉じた行の訂正は CONFLICT で、何も書かない" do
      row = prices.sole
      correct(row)

      expect(failures(correct(row, unit_price: 80, at: t2 + 1.day))).to eq([ [ :conflict, [ :item_price_id ] ] ])
      expect(prices.map(&:unit_price)).to eq([ 90 ])
    end

    it "理由が空か、単価が負か bigint の最大値を超えれば、項目を指す INVALID_INPUT。最大値ちょうどは受け付ける" do
      row = prices.sole

      expect(failures(correct(row, reason: " "))).to eq([ [ :invalid_input, [ :reason ] ] ])
      expect(failures(correct(row, unit_price: -1))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
      expect(failures(correct(row, unit_price: 9_223_372_036_854_775_808))).to eq([ [ :invalid_input, [ :unit_price ] ] ])
      expect(prices.map(&:unit_price)).to eq([ 100 ])
      expect(correct(row, unit_price: 9_223_372_036_854_775_807)).to be_success
    end

    # 理由の上限は 200 文字（docs/architecture/graphql-schema.md「mutation の一覧」）
    it "理由は 200 文字ちょうどを受け付け、201 文字は理由を指す INVALID_INPUT で何も書かない" do
      row = prices.sole

      expect(failures(correct(row, reason: "あ" * 201))).to eq([ [ :invalid_input, [ :reason ] ] ])
      expect(prices.map(&:unit_price)).to eq([ 100 ])
      expect(correct(row, reason: "あ" * 200)).to be_success
      expect(prices.map { [ _1.unit_price, _1.reason ] }).to eq([ [ 90, "あ" * 200 ] ])
    end

    it "見えない行は NOT_FOUND" do
      other = foreign[:price]

      expect(failures(described_class.correct(actor, item_price_id: other.id, unit_price: 1, reason: "誤り")))
        .to eq([ [ :not_found, [ :item_price_id ] ] ])
      expect(described_class.find(actor, other.id)).to be_nil
      expect(described_class.find(actor, prices.sole.id)).to have_attributes(item_id: item.id, unit_price: 100)
    end
  end

  describe ".price_at・.history" do
    it "品目ごとに引き、見えない品目は含まない" do
      others = foreign[:item]
      second = FactoryBot.create(:item, unit_price: 200)

      expect(described_class.price_at(actor, [ item.id, second.id, others.id ], valid_on: Date.current))
        .to eq(item.id => 100, second.id => 200)
      expect(described_class.history(actor, [ item.id, others.id ]).transform_values { _1.map(&:unit_price) })
        .to eq(item.id => [ 100 ], others.id => [])
    end
  end

  describe ".explain" do
    # 10/15 の受注で 100 円を写した明細。t1 に請求書を発行し、t2 に 10/15 の単価を 90 円に訂正する
    let(:line) do
      FactoryBot.create(:sales_order_line, :matched, item_id: item.id, unit_price: 100, priced_on: Date.new(2026, 10, 15))
    end

    before do
      travel_to(t2) { described_class.correct(actor, item_price_id: prices.sole.id, unit_price: 90, reason: "入力の誤り") }
    end

    it "写した単価と有効日と、発行の時点で信じていた単価と、いまの単価を別々に返す" do
      explanation = described_class.explain(actor, [ line.id ], as_of: t1).fetch(line.id)

      expect(explanation).to have_attributes(sales_order_line_id: line.id, ordered_unit_price: 100, priced_on: Date.new(2026, 10, 15),
        unit_price_as_of_issue: 100, unit_price_now: 90)
    end

    it "発行の時刻が無ければ（下書きと未請求の明細）、発行の時点の単価は空" do
      expect(described_class.explain(actor, [ line.id ], as_of: nil).fetch(line.id))
        .to have_attributes(unit_price_as_of_issue: nil, unit_price_now: 90)
    end

    it "見えない明細と照合前の明細は含まない" do
      unmatched = FactoryBot.create(:sales_order_line)
      others = foreign[:line]

      expect(described_class.explain(actor, [ line.id, unmatched.id, others.id ], as_of: t1).keys).to eq([ line.id ])
    end
  end
end
