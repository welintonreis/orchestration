# Records one heartbeat's metrics for an edge node and raises the same
# Alert thresholds MetricsJob uses for the local host — kept as a separate,
# small duplication rather than refactoring MetricsJob, since that job is
# already deployed/tested against the local host and dedups alerts without
# any notion of "which host": reusing it as-is would let one loud node
# suppress alerts for every other node hitting the same threshold.
class EdgeMetricsRecorder
  CPU_THRESHOLD  = ENV.fetch("CPU_THRESHOLD",  "85").to_f
  RAM_THRESHOLD  = ENV.fetch("RAM_THRESHOLD",  "90").to_f
  DISK_THRESHOLD = ENV.fetch("DISK_THRESHOLD", "80").to_f

  def self.record!(edge_node:, metrics:)
    host_metric = HostMetric.create!(
      edge_node:    edge_node,
      cpu_percent:  metrics["cpu_percent"].to_f,
      ram_percent:  metrics["ram_percent"].to_f,
      disk_percent: metrics["disk_percent"].to_f,
      swap_percent: metrics["swap_percent"].to_f,
      load_1m:      metrics["load_1m"].to_f,
      load_5m:      metrics["load_5m"].to_f,
      load_15m:     metrics["load_15m"].to_f
    )
    check_thresholds(edge_node, host_metric)
    host_metric
  end

  def self.check_thresholds(node, host_metric)
    {
      "cpu"  => [host_metric.cpu_percent, CPU_THRESHOLD],
      "ram"  => [host_metric.ram_percent, RAM_THRESHOLD],
      "disk" => [host_metric.disk_percent, DISK_THRESHOLD]
    }.each do |resource, (value, threshold)|
      next if value < threshold
      next if recent_alert?(node, resource)

      level = value >= threshold + 10 ? "critical" : "warning"
      Alert.create!(
        level:    level,
        resource: resource,
        message:  "Edge node \"#{node.name}\": #{resource.upcase} usage at #{value}% (threshold: #{threshold}%)"
      )
    end
  end

  def self.recent_alert?(node, resource)
    Alert.unread.by_resource(resource)
         .where(created_at: 5.minutes.ago..)
         .where("message LIKE ?", "%\"#{node.name}\"%")
         .exists?
  end
  private_class_method :check_thresholds, :recent_alert?
end
