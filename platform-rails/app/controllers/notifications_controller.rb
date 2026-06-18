class NotificationsController < ApplicationController
  POPOVER_LIMIT = 15

  def index
    @alerts = Alert.order(created_at: :desc).limit(100)
    @unread_count = Alert.where(read_at: nil).count
  end

  def mark_all_read
    Alert.where(read_at: nil).update_all(read_at: Time.current)

    respond_to do |format|
      format.turbo_stream do
        load_popover_alerts
        render turbo_stream: [
          turbo_stream.replace("notifications-popover-body", partial: "notifications/popover_body", locals: { alerts: @alerts, unread_count: @unread_count }),
          turbo_stream.replace("alert-badge", partial: "shared/alert_badge")
        ]
      end
      format.html { redirect_to notifications_path, notice: "Todas notificações marcadas como lidas." }
    end
  end

  def mark_read
    alert = Alert.find(params[:id])
    alert.mark_read! unless alert.read?

    respond_to do |format|
      format.turbo_stream do
        load_popover_alerts
        render turbo_stream: [
          turbo_stream.replace("notifications-popover-body", partial: "notifications/popover_body", locals: { alerts: @alerts, unread_count: @unread_count }),
          turbo_stream.replace("alert-badge", partial: "shared/alert_badge")
        ]
      end
      format.html { redirect_to notifications_path }
    end
  end

  private

  def load_popover_alerts
    @alerts = Alert.order(created_at: :desc).limit(POPOVER_LIMIT)
    @unread_count = Alert.where(read_at: nil).count
  end
end
