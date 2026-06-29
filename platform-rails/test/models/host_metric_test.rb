require "test_helper"

class HostMetricTest < ActiveSupport::TestCase
  test "valid metric" do
    m = HostMetric.new(cpu_percent: 50, ram_percent: 60, disk_percent: 40,
                       swap_percent: 5, load_1m: 0.8, load_5m: 0.7, load_15m: 0.5)
    assert m.valid?
  end

  test "requires all percent and load fields" do
    m = HostMetric.new
    assert_not m.valid?
    %i[cpu_percent ram_percent disk_percent load_1m load_5m load_15m].each do |field|
      assert m.errors[field].any?, "expected error on #{field}"
    end
  end

  test "rejects negative values" do
    m = HostMetric.new(cpu_percent: -1, ram_percent: 0, disk_percent: 0,
                       swap_percent: 0, load_1m: 0, load_5m: 0, load_15m: 0)
    assert_not m.valid?
    assert m.errors[:cpu_percent].any?
  end

  test "last_24h scope returns only recent records" do
    assert_includes HostMetric.last_24h, host_metrics(:recent_metric)
    assert_not_includes HostMetric.last_24h, host_metrics(:old_metric)
  end

  test "latest returns the most recently created record" do
    assert_equal host_metrics(:recent_metric), HostMetric.latest
  end

  test "swap_percent defaults to 0 when not provided" do
    m = HostMetric.create!(cpu_percent: 20, ram_percent: 30, disk_percent: 10,
                           load_1m: 0.1, load_5m: 0.1, load_15m: 0.1)
    assert_equal 0.0, m.swap_percent
  end
end
