module Notifications
  # 通知の本文（text だけ）。送信はジョブの中で deliver_now を呼び、配送の方法は Provider に渡す（docs/adr/007 代替案 3）
  class Mailer < ApplicationMailer
    # 開発の環境の既定（raise_delivery_errors = false）のままだと、送信の失敗をジョブが受け取れず、受け付けたと記録する
    self.raise_delivery_errors = true
    add_delivery_method :notifications_provider, Delivery
    self.delivery_method = :notifications_provider

    default from: -> { Rails.configuration.x.notifications.from }

    def received_invoice
      compose("請求書が届きました（#{params.fetch(:values).fetch('invoice_number')}）")
    end

    def new_sales_order
      compose("新しい受注があります（#{params.fetch(:values).fetch('order_no')}）")
    end

    private

    # 宛先・本文の値・提供元へ添える値（custom_args）は、ジョブが params で渡す。custom_args は Delivery が取り出す
    def compose(subject)
      @values = params.fetch(:values)
      headers[Delivery::CUSTOM_ARGS_HEADER] = params.fetch(:custom_args).to_json
      mail(to: params.fetch(:to), subject:)
    end
  end
end
