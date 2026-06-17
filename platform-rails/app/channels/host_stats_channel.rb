class HostStatsChannel < ApplicationCable::Channel
  PROC_PATH = ENV.fetch("PROC_PATH", "/proc")

  def subscribed
    @stop = false
    @stream_thread = Thread.new do
      loop do
        break if @stop
        transmit(collect_stats)
        sleep 5
      end
    rescue => e
      transmit({ error: e.message }) rescue nil
    end
  end

  def unsubscribed
    @stop = true
    @stream_thread&.kill
    @stream_thread = nil
  end

  private

  def collect_stats
    { cpu: read_cpu, ram: read_ram, disk: read_disk }
  end

  def read_cpu
    s1 = parse_stat
    sleep 1
    s2 = parse_stat
    total = s2.sum - s1.sum
    idle  = s2[3] - s1[3]
    return 0.0 if total == 0
    ((1.0 - idle.to_f / total) * 100).round(1)
  end

  def parse_stat
    File.read("#{PROC_PATH}/stat").lines.first.split[1..].map(&:to_i)
  end

  def read_ram
    data      = File.read("#{PROC_PATH}/meminfo")
    total     = data[/MemTotal:\s+(\d+)/, 1].to_i
    available = data[/MemAvailable:\s+(\d+)/, 1].to_i
    return 0.0 if total == 0
    (((total - available).to_f / total) * 100).round(1)
  end

  def read_disk
    `df / 2>/dev/null`.lines.last.to_s.split[4].to_s.tr("%", "").to_f
  rescue
    0.0
  end
end
