require "test_helper"

class AiQuotaHelperTest < ActionView::TestCase
  include AiQuotaHelper

  test "sparkline needs at least two points to mean anything" do
    assert_nil quota_sparkline([])
    assert_nil quota_sparkline([ [ Time.current, 50 ] ])
    assert_not_nil quota_sparkline([ [ 2.hours.ago, 90 ], [ Time.current, 10 ] ])
  end

  # SVG y grows downward, so a full quota must sit at the TOP of the box.
  # Getting this backwards draws every trend upside down.
  test "a full quota plots at the top and an empty one at the bottom" do
    svg = quota_sparkline([ [ 2.hours.ago, 100 ], [ Time.current, 0 ] ], width: 10, height: 20)
    points = svg[/points="([^"]+)"/, 1].split

    assert_equal "0.0,0.0", points.first
    assert_equal "10.0,20.0", points.last
  end

  test "countdown collapses to the largest useful unit" do
    # +1s so the seconds elapsed between building the time and reading it don't
    # round the minute down.
    assert_equal "2h 30m", quota_countdown(2.hours.from_now + 30.minutes + 1.second)
    assert_equal "45m", quota_countdown(45.minutes.from_now + 1.second)
    assert_equal "3d 2h", quota_countdown(3.days.from_now + 2.hours + 1.second)
    assert_equal "agora", quota_countdown(1.minute.ago)
    assert_nil quota_countdown(nil)
  end

  test "reset label distinguishes today from tomorrow" do
    assert_match(/\AHoje, /, quota_reset_at(Time.current.change(hour: 23, min: 0)))
    assert_match(/\AAmanhã, /, quota_reset_at(Date.current.tomorrow.noon))
  end

  test "usage label reads as counts, or as unlimited" do
    assert_equal "60 / 100", quota_usage_label(AiQuota::Quota.new(used: 60, total: 100))
    assert_equal "5 usado · ilimitado", quota_usage_label(AiQuota::Quota.new(used: 5, unlimited: true))
  end
end
