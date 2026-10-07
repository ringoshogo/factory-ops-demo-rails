# 所有ロールの接続。テストの中で一時的な表を作り、消すときだけ使う。
# 行の読み書きはアプリのロール（ActiveRecord::Base の接続）で行い、RLS を通す。
class OwnerConnection < ActiveRecord::Base
  self.abstract_class = true
  establish_connection configurations.configs_for(env_name: Rails.env, name: "owner")
end
