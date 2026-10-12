# 環境変数をブロックの間だけ変え、終わったら前の値に戻す。nil を渡すと消す
module EnvHelpers
  def with_env(values)
    previous = values.keys.to_h { [ _1, ENV[_1] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
