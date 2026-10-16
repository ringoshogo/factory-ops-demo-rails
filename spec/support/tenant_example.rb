# example をテナントで包む around から呼ぶ（docs/guides/testing.md「層への配分」）。
#
# Tenancy.with_tenant で example を直に包むと、example が SQL のエラーで落ちたときに around が送出する。rspec は example の例外を
# example.run の中で拾う（rspec-core 3.13.6 の lib/rspec/core/example.rb の Example#run）ので、with_tenant はそのまま
# 中断したトランザクションのセーブポイントを解放しようとして失敗する。外側の rspec-rails の around は、example ごとの
# トランザクションを before_setup で開いて after_teardown で巻き戻し、ensure で包まない（rspec-rails 8.0.4 の
# lib/rspec/rails/adapters.rb の MinitestLifecycleAdapter）ので、送出で後始末が飛ぶ。後始末は、トランザクションの巻き戻しと、
# example の間だけスレッドをまたいで共有させた接続（activerecord 8.1.4 の lib/active_record/test_fixtures.rb の
# teardown_transactional_fixtures が呼ぶ ConnectionPool#unpin_connection!）を戻すことである。残ったトランザクションは後ろの
# example に入れ子になり、所有ロールの接続に残ると後ろのグループのポリシーの足し外しが落ちる。共有のまま残った接続は、
# 後ろの競合テストの 2 つのスレッドに同じ接続を渡し、互いのロックを待たせて止める。
#
# 落ちた example のときだけ、ActiveRecord::Rollback でセーブポイントを巻き戻して抜ける。transaction は Rollback を飲み、
# requires_new のセーブポイントを巻き戻してから抜ける（activerecord 8.1.4 の
# lib/active_record/connection_adapters/abstract/database_statements.rb の transaction と、transaction.rb の within_new_transaction）。
# 中断したトランザクションが戻るので、with_tenant の後始末（Tenancy.reset!）も流れ、around は送出しない。
# 落ちたかの条件は、rspec-core が失敗を出すときに読む Example#display_exception（@exception || execution_result.pending_exception）と
# 同じ値にする。pending の example の例外は exception ではなく execution_result.pending_exception に入る（同じファイルの display_exception=）。
#
# 通った example は巻き戻さず、セーブポイントを解放して抜ける。このセーブポイントはテストの外側の結べないトランザクションの
# 直下にあるので、example の中の after_commit はこの解放で走る（transaction.rb の run_commit_callbacks = !current_transaction.joinable?）。
# いつも巻き戻すと、通った example の後に after_commit の代わりに after_rollback が走る
module TenantExample
  def self.run(example, tenant_id)
    Tenancy.with_tenant(tenant_id) do
      example.run
      raise ActiveRecord::Rollback if example.exception || example.execution_result.pending_exception
    end
  end
end
