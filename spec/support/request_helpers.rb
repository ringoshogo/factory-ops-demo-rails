# HTTP の要求を流す spec の補助（docs/guides/testing.md「層への配分」）。type: :request の spec と、
# 重要シナリオの補助（spec/support/scenarios.rb）が取り込む。spec の中で同じ名前のメソッドか let を定義すると、そちらが優先される
module RequestHelpers
  def login_as(user)
    post "/session", params: { email: user.email, password: "password" }, as: :json
    expect(response).to have_http_status(:no_content)
  end

  # 応答の本文をそのまま返す。トップレベルのエラーを確かめる example が使う
  def graphql_body(text, **variables)
    post "/graphql", params: { query: text, variables: }, as: :json
    response.parsed_body
  end

  # トップレベルのエラーがあれば落とし、data を返す
  def query(text, **variables)
    post "/graphql", params: { query: text, variables: }, as: :json
    expect(response.parsed_body["errors"]).to be_nil
    response.parsed_body.fetch("data")
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
