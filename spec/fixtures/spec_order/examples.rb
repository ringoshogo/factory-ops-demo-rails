# spec/platform/spec_order_spec.rb が子のプロセスで流す、10 個の example。名前が *_spec.rb でないので、全件の流れには入らない。
# rails_helper を読まないので、DB に触れず、呼ばれない公開 API の判定（spec/rails_helper.rb の after(:suite)）も通らない
RSpec.describe "並びを確かめる 10 個の example" do
  # 同じ seed で流した 2 回が同じ値を書くかで、Kernel.srand が seed で種を蒔いたかを確かめる
  it "1" do
    path = ENV["SPEC_ORDER_RAND_FILE"]
    File.write(path, Kernel.rand.to_s) if path
  end

  (2..10).each { |n| it(n.to_s) { expect(n).to be_positive } }
end
