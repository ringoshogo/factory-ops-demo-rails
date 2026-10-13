require "rails_helper"
require_relative "../support/env_helpers"

# 環境変数を変える補助（spec/support/env_helpers.rb）。戻し忘れると、後の example が前の example の値で動く
RSpec.describe EnvHelpers do
  include described_class

  let(:name) { "SPEC_ENV_HELPERS_#{SecureRandom.hex(4).upcase}" }

  after { ENV.delete(name) }

  it "ブロックの間だけ値を変え、終わったら前の値に戻す。前に無かった変数は消す" do
    ENV[name] = "before"
    with_env(name => "inside") { expect(ENV[name]).to eq("inside") }
    expect(ENV[name]).to eq("before")

    ENV.delete(name)
    with_env(name => "inside") { expect(ENV[name]).to eq("inside") }
    expect(ENV).not_to have_key(name)
  end

  it "ブロックが例外で終わっても前の値に戻し、nil を渡すと間だけ消す" do
    ENV[name] = "before"

    expect { with_env(name => "inside") { raise "spec" } }.to raise_error(RuntimeError, "spec")
    expect(ENV[name]).to eq("before")

    with_env(name => nil) { expect(ENV).not_to have_key(name) }
    expect(ENV[name]).to eq("before")
  end
end
