class MetricsController < ApplicationController
  PROC_PATH = ENV.fetch("PROC_PATH", "/proc")

  def latest
    @latest_metric = HostMetric.latest
    @metrics_24h   = HostMetric.last_24h.order(:created_at)
    render layout: false
  end

  def processes
    cpu1  = cpu_total
    snap1 = proc_snap_cpu

    sleep 1

    cpu2  = cpu_total
    snap2 = proc_snap_full

    total_delta = [cpu2 - cpu1, 1].max.to_f

    list = snap1.filter_map do |pid, s1|
      s2 = snap2[pid]
      next unless s2
      delta   = (s2[:utime] + s2[:stime]) - (s1[:utime] + s1[:stime])
      cpu_pct = (delta / total_delta * 100).round(1)
      { pid: pid, name: s2[:name], cpu: cpu_pct, mem_kb: s2[:mem_kb], docker: s2[:docker] }
    end

    @top_processes = list.sort_by { |p| [-p[:cpu], -p[:mem_kb]] }.first(12)
    render layout: false
  end

  private

  def cpu_total
    File.read("#{PROC_PATH}/stat").lines.first.split[1..].map(&:to_i).sum
  rescue
    0
  end

  def proc_snap_cpu
    Dir.glob("#{PROC_PATH}/[0-9]*/stat").each_with_object({}) do |path, h|
      pid  = path[%r{/(\d+)/stat$}, 1].to_i
      stat = File.read(path) rescue next
      m    = stat.match(/\A\d+ \(.+\) \S+(?: \S+){9} (\d+) (\d+)/)
      next unless m
      h[pid] = { utime: m[1].to_i, stime: m[2].to_i }
    end
  end

  def proc_snap_full
    Dir.glob("#{PROC_PATH}/[0-9]*/stat").each_with_object({}) do |path, h|
      pid    = path[%r{/(\d+)/stat$}, 1].to_i
      stat   = File.read(path) rescue next
      m      = stat.match(/\A\d+ \((.+)\) \S+(?: \S+){9} (\d+) (\d+)/)
      next unless m

      status = File.read("#{PROC_PATH}/#{pid}/status") rescue ""
      cgroup = File.read("#{PROC_PATH}/#{pid}/cgroup") rescue ""

      h[pid] = {
        name:   m[1],
        utime:  m[2].to_i,
        stime:  m[3].to_i,
        mem_kb: status[/VmRSS:\s+(\d+)/, 1].to_i,
        docker: cgroup.include?("docker")
      }
    end
  end
end
