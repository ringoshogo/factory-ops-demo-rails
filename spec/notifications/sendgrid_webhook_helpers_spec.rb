require "rails_helper"
require_relative "../support/sendgrid_webhook"

# Webhook のテストの補助が、設定した公開鍵を example の後に元へ戻す（spec/support/sendgrid_webhook.rb）
RSpec.describe SendgridWebhookHelpers do
  let(:key) { OpenSSL::PKey::EC.generate("prime256v1") }

  def configured = Rails.configuration.x.notifications.sendgrid_webhook_public_key

  it "ブロックの間だけ鍵を設定し、抜けたら元の値に戻す" do
    before = configured
    inside = nil

    described_class.with_public_key(key) { inside = configured }

    expect(inside).to eq(Base64.strict_encode64(key.public_to_der))
    expect(configured).to eq(before)
  end

  it "ブロックが例外で抜けても元の値に戻す" do
    before = configured

    expect { described_class.with_public_key(key) { raise "落ちた" } }.to raise_error("落ちた")

    expect(configured).to eq(before)
  end
end
