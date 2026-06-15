class AuditLogsController < ApplicationController
  before_action :require_admin!

  ACTIONS_PER_PAGE = 50

  def index
    @audit_logs = AuditLog.includes(:user).recent
    @audit_logs = @audit_logs.where(user_id: params[:user_id]) if params[:user_id].present?
    @audit_logs = @audit_logs.where("action LIKE ?", "%#{params[:action_filter]}%") if params[:action_filter].present?
    @audit_logs = @audit_logs.limit(ACTIONS_PER_PAGE).offset(page_offset)
    @total      = AuditLog.count
    @page       = current_page
    @users      = User.order(:email_address)
  end

  private

  def current_page
    [params[:page].to_i, 1].max
  end

  def page_offset
    (current_page - 1) * ACTIONS_PER_PAGE
  end
end
