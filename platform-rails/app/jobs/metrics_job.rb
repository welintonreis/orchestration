class MetricsJob < ApplicationJob
  queue_as :default

  PROC_PATH     = ENV.fetch("PROC_PATH", "/proc")
  CPU_THRESHOLD  = ENV.fetch("CPU_THRESHOLD",  "85").to_f
  RAM_THRESHOLD  = ENV.fetch("RAM_THRESHOLD",  "90").to_f
  DISK_THRESHOLD = ENV.fetch("DISK_THRESHOLD", "80").to_f
  SWAP_THRESHOLD = ENV.fetch("SWAP_THRESHOLD", "50").to_f

  def perform
    cpu       = read_cpu_percent
    ram       = read_ram_percent
    disk      = read_disk_percent
    swap      = read_swap_percent
    load_avgs = read_load_avg

    HostMetric.create!(
      cpu_percent:  cpu,
      ram_percent:  ram,
      disk_percent: disk,
      swap_percent: swap,
      load_1m:      load_avgs[0],
      load_5m:      load_avgs[1],
      load_15m:     load_avgs[2]
    )

    check_thresholds(cpu, ram, disk, swap)
    cleanup_old_metrics
  end

  private

  def read_cpu_percent
    s1 = parse_cpu_stat
    sleep 1
    s2 = parse_cpu_stat

    total_delta = s2.sum - s1.sum
    idle_delta  = s2[3] - s1[3]

    return 0.0 if total_delta == 0

    ((1.0 - idle_delta.to_f / total_delta) * 100).round(1)
  end

  def parse_cpu_stat
    line = File.read("#{PROC_PATH}/stat").lines.first
    line.split[1..].map(&:to_i)
  end

  def read_ram_percent
    data      = File.read("#{PROC_PATH}/meminfo")
    total     = data[/MemTotal:\s+(\d+)/, 1].to_i
    available = data[/MemAvailable:\s+(\d+)/, 1].to_i
    return 0.0 if total == 0

    (((total - available).to_f / total) * 100).round(1)
  end

  def read_disk_percent
    line = `df / 2>/dev/null`.lines.last.to_s.split
    line[4].to_s.tr("%", "").to_f
  rescue
    0.0
  end

  def read_swap_percent
    data  = File.read("#{PROC_PATH}/meminfo")
    total = data[/SwapTotal:\s+(\d+)/, 1].to_i
    free  = data[/SwapFree:\s+(\d+)/, 1].to_i
    return 0.0 if total == 0

    (((total - free).to_f / total) * 100).round(1)
  end

  def read_load_avg
    content = File.read("#{PROC_PATH}/loadavg")
    content.split.first(3).map(&:to_f)
  end

  def check_thresholds(cpu, ram, disk, swap)
    create_alert_if("cpu",  cpu,  CPU_THRESHOLD)
    create_alert_if("ram",  ram,  RAM_THRESHOLD)
    create_alert_if("disk", disk, DISK_THRESHOLD)
    create_alert_if("swap", swap, SWAP_THRESHOLD)
  end

  def create_alert_if(resource, value, threshold)
    return if value < threshold

    recent = Alert.unread.by_resource(resource)
                  .where(created_at: 5.minutes.ago..).exists?
    return if recent

    level = value >= threshold + 10 ? "critical" : "warning"
    Alert.create!(
      level:    level,
      resource: resource,
      message:  "#{resource.upcase} usage at #{value}% (threshold: #{threshold}%)"
    )
  end

  def cleanup_old_metrics
    HostMetric.where(created_at: ...24.hours.ago).delete_all
  end
end
