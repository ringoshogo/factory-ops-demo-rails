require_relative "bullet_safelist"

BulletSafelist.apply!

# Bullet は、作ったレコードを N+1 の候補から外し（1 件だけ読んだレコードと同じに扱う）、inverse_of で結んだ関連を読み込み済みとみなす。
# example の中で準備のデータを factory で作ると、公開 API が読み直した同じレコードも候補にならず、N+1 が見えない。
# そこで factory が動く間は検出を止める。factory の中の factory（関連）は、外側が止めたので何もしない
module BulletFactoryPause
  def self.start(_name, _id, _payload)
    paused.push(Bullet.start?)
    Bullet.pause if paused.last
  end

  def self.finish(_name, _id, _payload)
    Bullet.resume if paused.pop
  end

  def self.paused = Thread.current[:bullet_factory_pause] ||= []
end

ActiveSupport::Notifications.subscribe("factory_bot.run_factory", BulletFactoryPause)

# 各 example を Bullet.profile で包み、関連を 1 件ずつ読む N+1 を example の失敗にする
# （docs/architecture/graphql-schema.md「ページングと N+1」）。
# start_request と end_request だけで包むと、検出しても通知されないまま end_request が検出を消すので、example は通る。
# 次の example は包まない。
# - bullet: false：spec/requests の example（HTTP の要求は Bullet::Rack が同じ手順で包み、外でも包むと外の検出を上書きして消す）と、
#   包みの例外を確かめるために自分で Bullet.profile を呼ぶ example
# - :concurrency：別のスレッドで操作する。Bullet は検出の状態をスレッドごとに持つので、別のスレッドの読み込みは見えない
RSpec.configure do |config|
  config.around do |example|
    if example.metadata[:bullet] == false || example.metadata[:concurrency]
      example.run
    else
      Bullet.profile { example.run }
    end
  end
end
