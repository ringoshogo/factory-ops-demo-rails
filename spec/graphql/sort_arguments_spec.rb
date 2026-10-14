require "rails_helper"

# 一覧の並べ替えの列の数の上限（docs/architecture/graphql-schema.md「ページングと N+1」）。上限はスキーマに出ないので、
# 画面の上限だけを変えると、型の検査は通り、見出しで足した列が API のトップレベルのエラーになる
RSpec.describe Resolvers::SortArguments do
  it "画面の見出しで足せる列の数が、API の列の数の上限と同じ" do
    screen = Rails.root.join("frontend/lib/list.ts").read[/^export const MAX_SORTS = (\d+);$/, 1]

    expect(screen&.to_i).to eq(Page::MAX_SORTS)
  end
end
