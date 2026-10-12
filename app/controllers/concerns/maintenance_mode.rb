# メンテナンスの切り替え（docs/guides/config.md「メンテナンスの切り替え」）。環境変数 MAINTENANCE_MODE が立っていれば、
# 取り込んだコントローラは何も実行せずに 503 を返す。テナントの境界の不具合が疑われる間、業務の表を読み書きする入口を止める
# （docs/runbooks/rls-misconfiguration.md）。ログインと SendGrid の Webhook には取り込まない
module MaintenanceMode
  extend ActiveSupport::Concern

  included do
    # 本文の形の検査やセッションの確かめより先に止める。止めている間は、どの要求も同じ 503 にする
    prepend_before_action :reject_during_maintenance
  end

  # 値は Rails の真偽値の読み方で読む。0・false・off は立てない側に、それ以外の値は立てる側に倒す。
  # 要求ごとに読むが、環境変数はプロセスの起動の時に決まるので、切り替えはプロセスの再起動で効く
  def self.enabled? = ActiveModel::Type::Boolean.new.cast(ENV["MAINTENANCE_MODE"]) == true

  private

  def reject_during_maintenance
    head :service_unavailable if MaintenanceMode.enabled?
  end
end
