# テナントの表のモデルの基底クラス。Tenancy.with_tenant の外で、リレーションを作るか保存すると例外にする。
# RLS は設定を忘れたクエリを 0 行にするだけなので、アプリでは例外にして気付けるようにする（decisions.md 2 章）。
class TenantRecord < ApplicationRecord
  self.abstract_class = true

  before_save { Tenancy.require_tenant! }
  before_destroy { Tenancy.require_tenant! }

  class << self
    # 条件は足さず、テナントの設定だけを確かめる。相互アクセスの表に所有テナントの条件を既定で付けると、
    # 相手の行を読むたびに unscoped が要るからである（decisions.md 2 章）。
    # メソッドで定義すると、find・find_by の文のキャッシュも使われなくなり、毎回ここを通る
    def default_scope
      Tenancy.require_tenant!
      all
    end
  end
end
