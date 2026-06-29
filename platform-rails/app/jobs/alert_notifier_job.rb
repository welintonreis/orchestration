class AlertNotifierJob < ApplicationJob
  queue_as :default

  # POST alert JSON to the configured webhook URL (e.g. N8N endpoint).
  # One fire-and-forget per alert — no retries on failure to avoid flooding.
  def perform(alert_id)
    url = AppSetting.get("alert_webhook_url", default: "")
    return if url.blank?

    alert = Alert.find_by(id: alert_id)
    return unless alert

    payload = {
      level:     alert.level,
      resource:  alert.resource,
      message:   alert.message,
      created_at: alert.created_at.iso8601
    }.to_json

    Excon.post(url,
      body:    payload,
      headers: { "Content-Type" => "application/json", "User-Agent" => "RedhuskOrchestration/1.0" },
      expects: (200..299).to_a,
      connect_timeout: 5,
      read_timeout:    10
    )
  rescue => e
    Rails.logger.warn("[AlertNotifierJob] webhook delivery failed: #{e.message}")
  end
end
