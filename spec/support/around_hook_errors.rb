# example を包む around のフックが example.run の後に送出しても、rspec-rails の example ごとのトランザクションを巻き戻す。
# rspec-rails は、トランザクションの開始と巻き戻しを、example group に足す around のフックの before_setup と after_teardown で行い、
# ensure で包まない（rspec-rails 8.0.4 の lib/rspec/rails/adapters.rb の MinitestLifecycleAdapter）。そのため内側の around が
# example.run の後に送出すると after_teardown が飛び、トランザクションが接続に残って後ろの example に入れ子になる。
# Tenancy.with_tenant で包んだ example が SQL のエラーで落ちると、rspec が example の例外を拾うので with_tenant はセーブポイントを
# 解放しようとして失敗し、around から送出する。所有ロールの接続にトランザクションが残ると、後ろのグループが足すポリシーが
# コミットされず、表のロックを持ったまま世界を作る接続を待たせて rspec が止まる。
#
# rspec-rails の around より内側で、group の本文の around より外側に、送出を example の失敗に移すフックを置く。
# config.include は group を作るときに、本文より先に、登録の順に include する（rspec-core 3.13.6 の
# lib/rspec/core/example_group.rb の ExampleGroup.subclass が、本文の module_exec の前に set_it_up から
# lib/rspec/core/configuration.rb の Configuration#configure_group を呼ぶ）ので、rspec-rails の後に登録すれば、この順になる
module AroundHookErrors
  extend ActiveSupport::Concern

  included do |group|
    group.around do |example|
      example.run
    rescue RSpec::Core::Pending::SkipDeclaredInExample
      # skip は呼んだ時点で example を pending にしてあるので、送り返さずに巻き戻しへ戻る。送り返すと巻き戻しが飛ぶ
      nil
    rescue RSpec::Support::AllExceptionsExceptOnesWeMustNotRescue => e
      example.example.set_exception(e)
    end
  end
end
