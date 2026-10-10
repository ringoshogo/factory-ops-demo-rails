require "rails_helper"

# リポジトリの根の schema.graphql が、いまのスキーマの書き出しと一致する。型を変えて書き直しを忘れると落ちる
# （docs/architecture/graphql-schema.md「スキーマの変更と非推奨」）
RSpec.describe "schema.graphql" do
  it "FactoryOpsSchema の書き出しと一致する（bin/rails graphql:schema:idl で書き直す）" do
    dumped = Rails.root.join("schema.graphql")

    expect(dumped).to exist
    # graphql:schema:idl は末尾に改行が無ければ足して書く
    expect(dumped.read).to eq(FactoryOpsSchema.to_definition.chomp + "\n")
  end
end
