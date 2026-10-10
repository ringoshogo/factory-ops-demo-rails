# Rails は executor で包んだ処理（Web の要求とワーカーのジョブ）の終わりに、ログとエラー通知の文脈を空にする。
# example と、直接の perform_now で動かすジョブは executor の外にあるので、文脈が次の example へ持ち越される
# （docs/guides/config.md「ログ」）
RSpec.configure do |config|
  config.after do
    Rails.event.clear_context
    ActiveSupport::ExecutionContext.clear
  end
end
