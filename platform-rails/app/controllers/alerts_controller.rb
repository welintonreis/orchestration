class AlertsController < ApplicationController
  def index
    @alerts = Alert.recent.limit(100)
    @unread_count = Alert.unread.count
  end

  def mark_all_read
    Alert.mark_all_read!
    redirect_to alerts_path, notice: "All alerts marked as read."
  end
end
