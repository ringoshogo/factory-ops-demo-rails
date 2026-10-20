# spec/platform/public_api_returns_spec.rb が子のプロセスで流す、公開 API を呼ばない 1 つの example。
# 名前が *_spec.rb でないので、全件の流れには入らない
require "rails_helper"

RSpec.describe "公開 API を呼ばない 1 つの example" do
  it { expect(1).to eq(1) }
end
