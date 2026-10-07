class ApplicationController < ActionController::API
  # 他サイトのフォームは application/json を送れない。送るには CORS のプリフライトが要るので、CSRF を防げる
  before_action :require_json

  private

  def require_json
    head :unsupported_media_type unless request.media_type == "application/json"
  end
end
