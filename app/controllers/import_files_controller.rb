# 取り込むファイルの受け口（docs/adr/007 決定 5 の A-4）。ブラウザが multipart/form-data で CSV を送るので、
# ApplicationController の application/json の制限を外し、代わりに Origin ヘッダを許可した origin と比べて CSRF を防ぐ
# （docs/guides/config.md「CSRF を防ぐ前提：CORS を開けない」）。ファイルを置くだけで、業務の表には何も起きない
class ImportFilesController < ApplicationController
  skip_before_action :require_json
  before_action :require_allowed_origin

  # GraphqlController と同じく、セッションのユーザーと世代を確かめてから、セッションのテナントで書く
  def create
    return head :unauthorized if session[:tenant_id].blank? || session[:user_id].blank?

    file = params[:file]
    return head :bad_request unless file.is_a?(ActionDispatch::Http::UploadedFile)
    # 読む前に大きさで拒む。上限を超えたファイルを、メモリに読み込まない
    return head :content_too_large if file.size > Imports::Files::MAX_BYTES

    actor = result = nil
    Tenancy.with_tenant(session[:tenant_id]) do
      actor = Partnerships::Authentication.actor(session[:user_id], session_version: session[:session_version])
      result = Imports::Files.store(actor, filename: file.original_filename, content: file.read) if actor
    end
    return head :unauthorized unless actor

    render json: result.value.to_h.transform_keys { _1.to_s.camelize(:lower) }, status: :created
  end

  private

  # ブラウザは別のオリジンからの POST にも Origin を付ける。Origin の無い要求も拒む
  def require_allowed_origin
    head :forbidden unless request.origin.present? && request.origin == Rails.configuration.x.frontend_origin
  end
end
