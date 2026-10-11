module Notifications
  # 通知の種類の登録（docs/adr/007 決定 4）。種類ごとに、保証と本文の値の項目を決める。
  # 保証は送り先ではなく、失ったときの影響で決める。critical は確実な外部送信（A-2）、best_effort は撃ちっぱなし（B-1）。
  # 呼び出し元が種類ごとに 1 か所で、ここに登録した種類だけを送ることは spec/notifications/call_sites_spec.rb が確かめる
  module Catalog
    Kind = Data.define(:name, :guarantee, :params)

    KINDS = [
      # 購買の「請求書発行」の受け手が、受領請求書を書くのと同じトランザクションで、発注側の admin へ送る
      Kind.new(name: :received_invoice, guarantee: :critical, params: %w[invoice_number issued_on total]),
      # 受注側が受注を確定したときに、受注側の admin へ送る。受注は画面の一覧に出るので、失っても業務は進む
      Kind.new(name: :new_sales_order, guarantee: :best_effort, params: %w[order_no])
    ].index_by(&:name).freeze

    def self.fetch(name, guarantee:)
      kind = KINDS.fetch(name.to_sym) { raise ArgumentError, "登録の無い通知の種類: #{name.inspect}" }
      raise ArgumentError, "#{name} の保証は #{kind.guarantee}" unless kind.guarantee == guarantee

      kind
    end

    # 本文の値は、種類が決めた項目の文字列だけを受け取る。メールアドレスや自由記述を送信記録とジョブの引数に入れない
    def self.validate_params!(kind, params)
      params = params.transform_keys(&:to_s)
      raise ArgumentError, "#{kind.name} の本文の値は #{kind.params.join('・')}: #{params.keys.sort.join('・')}" unless params.keys.sort == kind.params.sort
      raise ArgumentError, "#{kind.name} の本文の値は文字列で渡す" unless params.values.all?(String)

      params
    end
  end
end
