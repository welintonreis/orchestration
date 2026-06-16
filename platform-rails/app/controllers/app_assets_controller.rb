class AppAssetsController < ApplicationController
  skip_before_action :require_authentication

  def show
    asset = AppAsset.find_by!(key: params[:key])
    expires_in 1.week, public: true
    send_data asset.data, type: asset.content_type, disposition: "inline"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
