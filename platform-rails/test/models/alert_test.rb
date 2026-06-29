require "test_helper"

class AlertTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "valid alert" do
    assert Alert.new(level: "warning", resource: "cpu", message: "high").valid?
  end

  test "requires level, resource, message" do
    alert = Alert.new
    assert_not alert.valid?
    assert alert.errors[:level].any?
    assert alert.errors[:resource].any?
    assert alert.errors[:message].any?
  end

  test "rejects unknown level" do
    alert = Alert.new(level: "emergency", resource: "cpu", message: "x")
    assert_not alert.valid?
  end

  test "unread scope returns alerts with nil read_at" do
    assert_includes Alert.unread, alerts(:unread_warning)
    assert_includes Alert.unread, alerts(:critical_alert)
    assert_not_includes Alert.unread, alerts(:read_alert)
  end

  test "critical scope returns only critical level" do
    assert_includes Alert.critical, alerts(:critical_alert)
    assert_not_includes Alert.critical, alerts(:unread_warning)
  end

  test "mark_read! sets read_at" do
    alert = alerts(:unread_warning)
    assert_nil alert.read_at
    alert.mark_read!
    assert_not_nil alert.reload.read_at
  end

  test "mark_all_read! marks all unread alerts" do
    Alert.mark_all_read!
    assert_equal 0, Alert.unread.count
  end

  test "read? returns false when read_at is nil" do
    assert_not alerts(:unread_warning).read?
  end

  test "read? returns true when read_at is set" do
    assert alerts(:read_alert).read?
  end

  test "creates AlertNotifierJob after_create when webhook url configured" do
    AppSetting.set("alert_webhook_url", "https://n8n.example.com/webhook/test")
    assert_enqueued_with(job: AlertNotifierJob) do
      Alert.create!(level: "warning", resource: "cpu", message: "test webhook")
    end
  end

  test "does not enqueue AlertNotifierJob when no webhook url" do
    AppSetting.find_by(key: "alert_webhook_url")&.destroy
    assert_no_enqueued_jobs only: AlertNotifierJob do
      Alert.create!(level: "info", resource: "disk", message: "no webhook")
    end
  end
end
