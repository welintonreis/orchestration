require "test_helper"

class AlertNotifierJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "posts alert JSON to webhook URL" do
    AppSetting.set("alert_webhook_url", "https://n8n.example.com/webhook/alerts")
    alert = alerts(:unread_warning)
    posted_body = nil

    Excon.defaults[:mock] = true
    Excon.stub({}) do |params|
      posted_body = params[:body]
      { status: 200, body: "ok" }
    end

    AlertNotifierJob.perform_now(alert.id)

    assert_not_nil posted_body
    data = JSON.parse(posted_body)
    assert_equal alert.level, data["level"]
    assert_equal alert.resource, data["resource"]
    assert_equal alert.message, data["message"]
  ensure
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  test "skips when no webhook URL configured" do
    AppSetting.find_by(key: "alert_webhook_url")&.destroy
    alert = alerts(:unread_warning)

    call_count = 0
    Excon.defaults[:mock] = true
    Excon.stub({}) { call_count += 1; { status: 200, body: "ok" } }

    AlertNotifierJob.perform_now(alert.id)

    assert_equal 0, call_count
  ensure
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  test "skips when alert not found" do
    AppSetting.set("alert_webhook_url", "https://n8n.example.com/webhook/alerts")
    call_count = 0

    Excon.defaults[:mock] = true
    Excon.stub({}) { call_count += 1; { status: 200, body: "ok" } }

    AlertNotifierJob.perform_now(999_999)

    assert_equal 0, call_count
  ensure
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  test "logs warning but does not raise on webhook failure" do
    AppSetting.set("alert_webhook_url", "https://n8n.example.com/webhook/alerts")
    alert = alerts(:unread_warning)

    Excon.defaults[:mock] = true
    Excon.stub({}) { raise Excon::Error::Timeout, "timeout" }

    assert_nothing_raised { AlertNotifierJob.perform_now(alert.id) }
  ensure
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end
end
