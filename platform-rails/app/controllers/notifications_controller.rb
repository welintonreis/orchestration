class NotificationsController < ApplicationController
  def index
    @alerts = Alert.order(created_at: :desc).limit(100)
    @unread_count = Alert.where(read_at: nil).count
  end

  def mark_all_read
    Alert.where(read_at: nil).update_all(read_at: Time.current)
    redirect_to notifications_path, notice: "Todas notificações marcadas como lidas."
  end
end
