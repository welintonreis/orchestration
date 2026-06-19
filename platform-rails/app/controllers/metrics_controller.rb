class MetricsController < ApplicationController
  PROC_PATH = ENV.fetch("PROC_PATH", "/proc")
  HZ        = 100.0  # standard Linux CLK_TCK

  def latest
    @latest_metric = HostMetric.latest
    @metrics_24h   = HostMetric.last_24h.order(:created_at)
    render layout: false
  end

  def processes
    total_mem_kb = read_total_mem
    uptime_secs  = read_uptime

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
      mem_pct = total_mem_kb > 0 ? (s2[:mem_kb] / total_mem_kb.to_f * 100).round(1) : 0.0
      proc_uptime = uptime_secs > 0 && s2[:starttime] > 0 ? uptime_secs - s2[:starttime] / HZ : nil

      {
        pid:        pid,
        name:       s2[:name],
        state:      s2[:state],
        threads:    s2[:threads],
        cpu:        cpu_pct,
        mem_kb:     s2[:mem_kb],
        mem_pct:    mem_pct,
        uptime_sec: proc_uptime,
        docker:     s2[:docker]
      }
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

  def read_total_mem
    File.read("#{PROC_PATH}/meminfo")[/MemTotal:\s+(\d+)/, 1].to_i
  rescue
    0
  end

  def read_uptime
    File.read("#{PROC_PATH}/uptime").split.first.to_f
  rescue
    0.0
  end

  # Minimal first snapshot — only needs utime+stime for delta
  # /proc/[pid]/stat fields: pid (name) state ppid pgrp session tty_nr tpgid
  #   flags minflt cminflt majflt cmajflt utime(14) stime(15) ...
  def proc_snap_cpu
    Dir.glob("#{PROC_PATH}/[0-9]*/stat").each_with_object({}) do |path, h|
      pid  = path[%r{/(\d+)/stat$}, 1].to_i
      stat = File.read(path) rescue next
      # state(3) then 10 fields (ppid–cmajflt) then utime(14) stime(15)
      m = stat.match(/\A\d+ \(.+\) \S+(?: \S+){10} (\d+) (\d+)/)
      next unless m
      h[pid] = { utime: m[1].to_i, stime: m[2].to_i }
    end
  end

  # Full snapshot — collects all displayable fields
  def proc_snap_full
    Dir.glob("#{PROC_PATH}/[0-9]*/stat").each_with_object({}) do |path, h|
      pid  = path[%r{/(\d+)/stat$}, 1].to_i
      stat = File.read(path) rescue next

      # state(3), 10 fields(ppid–cmajflt), utime(14), stime(15),
      # 6 fields(cutime–itrealvalue), starttime(22)
      m = stat.match(/\A\d+ \((.+)\) (\S+)(?: \S+){10} (\d+) (\d+)(?: \S+){6} (\d+)/)
      next unless m

      status = File.read("#{PROC_PATH}/#{pid}/status") rescue ""
      cgroup = File.read("#{PROC_PATH}/#{pid}/cgroup") rescue ""

      h[pid] = {
        name:      m[1],
        state:     m[2],
        utime:     m[3].to_i,
        stime:     m[4].to_i,
        starttime: m[5].to_i,
        mem_kb:    status[/VmRSS:\s+(\d+)/, 1].to_i,
        threads:   status[/Threads:\s+(\d+)/, 1].to_i,
        docker:    cgroup.include?("docker")
      }
    end
  end
end
