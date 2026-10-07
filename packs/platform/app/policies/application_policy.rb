# 各コンテキストの policy の基底。user には操作者（Partnerships::Actor）が入る。
# 規則を書かなければ拒否する（ActionPolicy::Base の既定の規則はすべて偽）
class ApplicationPolicy < ActionPolicy::Base
end
