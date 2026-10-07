require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../lib/rubocop/cop/factory_ops/event_job_enqueue"

RSpec.describe RuboCop::Cop::FactoryOps::EventJobEnqueue, :config do
  it "Contracts::EventJob の登録を落とす" do
    expect_offense(<<~RUBY)
      Contracts::EventJob.perform_later("Contracts::OrderPlaced", {}, "Sales::Receiver", tenant_id)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Contracts::EventJob は Contracts.publish から登録する。
      ::Contracts::EventJob.set(wait: 1).perform_later
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Contracts::EventJob は Contracts.publish から登録する。
      Contracts::EventJob.new(name, payload, receiver, tenant_id).enqueue
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Contracts::EventJob は Contracts.publish から登録する。
      Contracts::EventJob.publishing { job.enqueue }
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Contracts::EventJob は Contracts.publish から登録する。
    RUBY
  end

  it "SolidQueue::Job への直接の書き込みを落とす" do
    expect_offense(<<~RUBY)
      SolidQueue::Job.enqueue(job)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ SolidQueue::Job に直接書かず、Active Job から登録する。
      SolidQueue::Job.create!(class_name: "Contracts::EventJob")
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ SolidQueue::Job に直接書かず、Active Job から登録する。
    RUBY
  end

  it "発行口と、キューの行の読み取りは通す" do
    expect_no_offenses(<<~RUBY)
      Contracts.publish(event)
      SolidQueue::Job.where(finished_at: nil).order(:id)
      ApplicationJob.perform_later
    RUBY
  end
end
