require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/cop/factory_ops/external_effect_enqueue"

RSpec.describe RuboCop::Cop::FactoryOps::ExternalEffectEnqueue, :config do
  let(:cop_config) { { "Jobs" => %w[Notifications::CriticalDeliveryJob Notifications::BestEffortMailJob] } }

  it "外部へ作用するジョブの登録と実行を落とす" do
    expect_offense(<<~RUBY)
      Notifications::CriticalDeliveryJob.perform_later(id)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 外部へ作用するジョブは Notifications::Email から登録する。
      ::Notifications::BestEffortMailJob.set(wait: 1).perform_later("new_sales_order", {})
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 外部へ作用するジョブは Notifications::Email から登録する。
      CriticalDeliveryJob.perform_now(id)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 外部へ作用するジョブは Notifications::Email から登録する。
      Notifications::CriticalDeliveryJob.new(id).enqueue
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 外部へ作用するジョブは Notifications::Email から登録する。
    RUBY
  end

  it "Action Mailer の deliver_later を、受け手を問わず落とす" do
    expect_offense(<<~RUBY)
      Notifications::Mailer.with(values: values).received_invoice.deliver_later
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ deliver_later を使わない。通知は Notifications::Email から送る。
      mail.deliver_later!(wait: 1)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ deliver_later を使わない。通知は Notifications::Email から送る。
    RUBY
  end

  it "登録口の呼び出し、他のジョブの登録、受け手の無い呼び出し、ジョブの中の deliver_now は通す" do
    expect_no_offenses(<<~RUBY)
      Notifications::Email.deliver_critical(:received_invoice, key: key, params: params)
      Notifications::ProcessInboxJob.perform_later
      ApplicationJob.perform_later
      job.perform_now
      perform_later(id)
      Notifications::Mailer.with(values: values).received_invoice.deliver_now
    RUBY
  end
end
