require "rails_helper"
require_relative "../../../../../spec/support/cross_read"

# 外部へのメールの登録口（docs/adr/007 決定 4・5）。確実な送信は送信記録とジョブを業務と同じトランザクションで確定させ、
# 撃ちっぱなしは記録を作らずにコミットの後に登録する
RSpec.describe Notifications::Email do
  let!(:tenant) { FactoryBot.create(:tenant).id }
  let!(:admins) { Tenancy.with_tenant(tenant) { FactoryBot.create_list(:user, 2, :admin) } }
  let!(:member) { Tenancy.with_tenant(tenant) { FactoryBot.create(:user) } }
  let(:invoice_params) { { invoice_number: "INV-000001", issued_on: "2026-10-12", total: "1100" } }

  # 別の example がコミットしたジョブを数えないよう、このテナントの名義のジョブに絞る
  def jobs(class_name) = SolidQueue::Job.where(class_name:, finished_at: nil).where("arguments LIKE ?", "%#{tenant}%")
  def deliveries = Tenancy.with_tenant(tenant) { Notifications::EmailDelivery.order(:id).to_a }

  describe ".deliver_critical" do
    def deliver(key: "received_invoice:1", params: invoice_params)
      Tenancy.with_tenant(tenant) { described_class.deliver_critical(:received_invoice, key:, params:) }
    end

    it "自社の admin を宛先にした送信記録と、その送信記録の送信のジョブを書く" do
      deliver

      expect(deliveries.map { _1.slice(:notification_key, :kind, :params, :attempts) }).to eq([
        { "notification_key" => "received_invoice:1", "kind" => "received_invoice",
          "params" => { "invoice_number" => "INV-000001", "issued_on" => "2026-10-12", "total" => "1100" }, "attempts" => 0 }
      ])
      expect(deliveries.first.recipient_user_ids).to match_array(admins.map(&:id))
      expect(jobs("Notifications::CriticalDeliveryJob").map { _1.arguments.dig("arguments", 0) }).to eq([ deliveries.first.id ])
      expect(jobs("Notifications::CriticalDeliveryJob").pluck(:queue_name)).to eq([ "external_mail" ])
    end

    it "同じ通知キーの 2 回目は、送信記録もジョブも足さない。別の通知キーなら足す" do
      expect(2.times.map { deliver }).to eq([ deliveries.sole.id, nil ])
      expect([ deliveries.size, jobs("Notifications::CriticalDeliveryJob").count ]).to eq([ 1, 1 ])

      deliver(key: "received_invoice:2")
      expect([ deliveries.size, jobs("Notifications::CriticalDeliveryJob").count ]).to eq([ 2, 2 ])
    end

    it "業務のトランザクションを戻すと、送信記録もジョブも残らない" do
      in_transaction = nil
      Tenancy.with_tenant(tenant) do
        described_class.deliver_critical(:received_invoice, key: "received_invoice:1", params: invoice_params)
        in_transaction = [ Notifications::EmailDelivery.count, jobs("Notifications::CriticalDeliveryJob").count ]
        raise ActiveRecord::Rollback
      end

      # コミットの後に回さず、送信記録と同じトランザクションの中でジョブの行を書いている
      expect(in_transaction).to eq([ 1, 1 ])
      expect([ deliveries.size, jobs("Notifications::CriticalDeliveryJob").count ]).to eq([ 0, 0 ])
    end

    it "登録の無い種類、撃ちっぱなしの種類、項目の合わない本文の値を拒む" do
      Tenancy.with_tenant(tenant) do
        expect { described_class.deliver_critical(:unknown, key: "k", params: {}) }.to raise_error(ArgumentError, /登録の無い/)
        expect { described_class.deliver_critical(:new_sales_order, key: "k", params: { order_no: "SO-1" }) }
          .to raise_error(ArgumentError, /best_effort/)
        expect { described_class.deliver_critical(:received_invoice, key: "k", params: invoice_params.merge(email: "a@example.com")) }
          .to raise_error(ArgumentError, /本文の値/)
        expect { described_class.deliver_critical(:received_invoice, key: "k", params: invoice_params.merge(total: 1100)) }
          .to raise_error(ArgumentError, /文字列/)
      end
      expect(deliveries).to be_empty
    end

    it "テナントの外では呼べない" do
      expect { described_class.deliver_critical(:received_invoice, key: "k", params: invoice_params) }
        .to raise_error(Tenancy::MissingTenant)
    end
  end

  describe ".deliver_best_effort" do
    it "送信記録を作らず、撃ちっぱなしのジョブを登録する" do
      Tenancy.with_tenant(tenant) { described_class.deliver_best_effort(:new_sales_order, params: { order_no: "SO-000001" }) }

      expect(deliveries).to be_empty
      job = jobs("Notifications::BestEffortMailJob").sole
      expect([ job.queue_name, ActiveJob::Arguments.deserialize(job.arguments["arguments"]), job.arguments["tenant_id"] ])
        .to eq([ "external_mail", [ "new_sales_order", { "order_no" => "SO-000001" } ], tenant ])
    end

    it "コミットの後に登録するので、業務のトランザクションを戻すとジョブも登録されない" do
      Tenancy.with_tenant(tenant) do
        described_class.deliver_best_effort(:new_sales_order, params: { order_no: "SO-000001" })
        expect(jobs("Notifications::BestEffortMailJob").count).to eq(0)
        raise ActiveRecord::Rollback
      end
      expect(jobs("Notifications::BestEffortMailJob").count).to eq(0)

      # 同じ呼び出しを確定させれば、コミットの後に登録される（対照）
      Tenancy.with_tenant(tenant) { described_class.deliver_best_effort(:new_sales_order, params: { order_no: "SO-000001" }) }
      expect(jobs("Notifications::BestEffortMailJob").count).to eq(1)
    end

    it "確実な送信の種類を拒む" do
      Tenancy.with_tenant(tenant) do
        expect { described_class.deliver_best_effort(:received_invoice, params: invoice_params) }
          .to raise_error(ArgumentError, /critical/)
      end
    end
  end

  describe ".redeliver_failed" do
    let(:at) { Time.zone.parse("2026-10-12 10:00") }

    it "since 以降に失敗した送信記録の失敗を消し、同じ送信記録のジョブを登録し直す。新しい送信記録は作らない" do
      failed, old, accepted = Tenancy.with_tenant(tenant) do
        [ FactoryBot.create(:email_delivery, failed_at: at, failure_reason: "retries_exhausted:http_503", attempts: 8),
          FactoryBot.create(:email_delivery, failed_at: at - 2.days, failure_reason: "http_400"),
          # 受け付けた送信記録は、失敗の時刻があっても送り直さない
          FactoryBot.create(:email_delivery, accepted_at: at, failed_at: at, failure_reason: "http_500") ]
      end

      count = Tenancy.with_tenant(tenant) { described_class.redeliver_failed(since: at - 1.day) }

      expect(count).to eq(1)
      expect(deliveries.size).to eq(3)
      Tenancy.with_tenant(tenant) do
        expect(failed.reload.slice(:failed_at, :failure_reason, :attempts).values).to eq([ nil, nil, 8 ])
        expect(old.reload.failed_at).to eq(at - 2.days)
      end
      expect(jobs("Notifications::CriticalDeliveryJob").map { _1.arguments.dig("arguments", 0) }).to eq([ failed.id ])
      expect(Tenancy.with_tenant(tenant) { accepted.reload.failed_at }).to eq(at)
    end

    # 操作者のいない入口（rake タスク）の公開 API なので、所有の条件を RLS に任せない。送信記録を FOR UPDATE で引くので、
    # SELECT だけを開いても RLS の UPDATE のポリシーが他社の行を除き、条件の抜けが見えない（docs/guides/testing.md「行列テストとの分担」）
    describe "RLS の SELECT と UPDATE を開いたとき" do
      include_context "RLS の SELECT と UPDATE を開く"

      it "他社の失敗した送信記録を送り直さず、変えない" do
        theirs = Tenancy.with_tenant(FactoryBot.create(:tenant).id) do
          FactoryBot.create(:email_delivery, failed_at: at, failure_reason: "http_503")
        end
        mine = Tenancy.with_tenant(tenant) { FactoryBot.create(:email_delivery, failed_at: at, failure_reason: "http_503") }

        Tenancy.with_tenant(tenant) do
          cross_read!
          # 対照：開いた後は、他社の送信記録が見え、自社の送信記録は送り直す
          before = reread(theirs)
          expect(described_class.redeliver_failed(since: at - 1.day)).to eq(1)
          expect(mine.reload.failed_at).to be_nil
          expect(reread(theirs)).to eq(before)
        end
      end
    end
  end
end
