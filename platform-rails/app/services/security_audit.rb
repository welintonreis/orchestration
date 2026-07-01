# Reads the HOST network namespace (via the bind-mounted /host/proc) and
# reports every TCP socket that LISTENs on a public address. Runs entirely
# inside the container — no ss/netstat/ufw needed: /proc/1/net/tcp{,6} is the
# same data `ss -tln` parses, and PID 1 is the host init so its net namespace
# is the host's (reading /proc/net/* would give the *container's* namespace).
#
# Phase 1: port-exposure surface (above). Phase 2: SSH brute-force, fail2ban
# and firewall state, read from #host_state — a JSON file a host-side cron
# (/usr/local/bin/security-collect.sh) writes every 5 min, bind-mounted
# read-only, since the container has no journald/firewall access of its own.
# See SECURITY-ROADMAP.md.
class SecurityAudit
  require "json"

  # Ports allowed to face the internet. Everything else public is a finding.
  PUBLIC_OK = {
    22  => "SSH",
    80  => "HTTP (Traefik)",
    443 => "HTTPS (Traefik)"
  }.freeze

  # Sensitive services that must never be world-reachable.
  SENSITIVE = {
    2375  => "Docker API (sem TLS)", 2376 => "Docker API", 2377 => "Swarm mgmt",
    4789  => "Swarm overlay (VXLAN)", 7946 => "Swarm gossip",
    3306  => "MySQL", 5432 => "PostgreSQL", 5436 => "PostgreSQL (extra)", 6432 => "PgBouncer",
    6379  => "Redis", 6380 => "Redis", 11211 => "Memcached",
    9000  => "MinIO API", 9001 => "MinIO console",
    11434 => "Ollama (LLM, sem auth)",
    5672  => "RabbitMQ", 15672 => "RabbitMQ admin",
    9092  => "Kafka", 2181 => "Zookeeper",
    27017 => "MongoDB", 9200 => "Elasticsearch", 5601 => "Kibana",
    8404  => "HAProxy stats", 9443 => "Portainer", 8080 => "HTTP interno"
  }.freeze

  SEV_ORDER = { critical: 0, warning: 1, ok: 2 }.freeze

  Finding = Struct.new(:proto, :port, :address, :service, :severity, :note, keyword_init: true)

  def initialize(proc_path: ENV.fetch("PROC_PATH", "/proc"),
                 security_path: ENV.fetch("HOST_SECURITY_PATH", "/host/security/state.json"),
                 container_diff_path: ENV.fetch("CONTAINER_DIFF_PATH", "/host/security/container-diff.json"))
    @proc_path           = proc_path
    @security_path       = security_path
    @container_diff_path = container_diff_path
  end

  def findings
    @findings ||= host_listeners
      .map { |proto, addr, port| classify(proto, addr, port) }
      .sort_by { |f| [ SEV_ORDER[f.severity], f.port ] }
  end

  def summary
    g = findings.group_by(&:severity)
    {
      critical: g.fetch(:critical, []).size,
      warning:  g.fetch(:warning, []).size,
      ok:       g.fetch(:ok, []).size,
      total:    findings.size
    }
  end

  # 0–100, lower is worse. Each exposed sensitive service costs 20, each
  # unknown public port 8.
  def score
    penalty = findings.sum { |f| f.severity == :critical ? 20 : f.severity == :warning ? 8 : 0 }
    [ 100 - penalty, 0 ].max
  end

  def collected_at = Time.current

  # Fase 2: facts the host-side cron collector wrote (brute-force, fail2ban,
  # firewall) — nil if the collector hasn't run yet or the mount is missing.
  def host_state
    return @host_state if defined?(@host_state)
    @host_state = JSON.parse(File.read(@security_path), symbolize_names: true)
  rescue StandardError
    @host_state = nil
  end

  # `docker diff` vs image for every running container, on its own (slower)
  # cron cadence — /usr/local/bin/container-diff-collect.sh. Flags new/changed
  # files in binary dirs, cron/systemd persistence, ssh key or account
  # tampering. nil if the collector hasn't run yet.
  def container_diff
    return @container_diff if defined?(@container_diff)
    @container_diff = JSON.parse(File.read(@container_diff_path), symbolize_names: true)
  rescue StandardError
    @container_diff = nil
  end

  private

  def classify(proto, addr, port)
    if SENSITIVE.key?(port)
      Finding.new(proto:, port:, address: addr, service: SENSITIVE[port],
                  severity: :critical, note: "Serviço sensível exposto à internet")
    elsif PUBLIC_OK.key?(port)
      Finding.new(proto:, port:, address: addr, service: PUBLIC_OK[port],
                  severity: :ok, note: "Exposição esperada")
    else
      Finding.new(proto:, port:, address: addr, service: "Serviço desconhecido",
                  severity: :warning, note: "Porta pública não catalogada")
    end
  end

  # => [["tcp", "0.0.0.0", 11434], ...] ; deduped by [proto, port].
  def host_listeners
    { "#{@proc_path}/1/net/tcp" => false, "#{@proc_path}/1/net/tcp6" => true }.flat_map do |path, v6|
      next [] unless File.exist?(path)

      File.foreach(path).with_index.filter_map do |line, i|
        next if i.zero? # header
        cols = line.split
        next unless cols[3] == "0A" # 0A = TCP_LISTEN
        hex_addr, hex_port = cols[1].split(":")
        next if loopback?(hex_addr, v6)
        [ v6 ? "tcp6" : "tcp", pretty(hex_addr, v6), hex_port.to_i(16) ]
      end
    end.uniq { |proto, _addr, port| [ proto, port ] }
  rescue StandardError
    []
  end

  # /proc stores addresses little-endian. v4: first octet = string bytes [6,8].
  def loopback?(hex, v6)
    if v6
      hex == "00000000000000000000000001000000" # ::1
    else
      hex[6, 2].to_i(16) == 127 # 127.0.0.0/8 (incl. systemd-resolve 127.0.0.53)
    end
  end

  def pretty(hex, v6)
    return "::" if v6 && hex == "00000000000000000000000000000000"
    return hex.scan(/.{4}/).join(":") if v6
    return "0.0.0.0" if hex == "00000000"
    hex.scan(/../).reverse.map { |b| b.to_i(16) }.join(".")
  end
end

# Self-check (ponytail): runs only when executed directly, never under Zeitwerk.
#   ruby app/services/security_audit.rb
if __FILE__ == $PROGRAM_NAME
  require "tmpdir"
  require "fileutils"
  Dir.mktmpdir do |dir|
    FileUtils.mkdir_p("#{dir}/1/net")
    # cols: sl local rem st ... ; 0A = LISTEN. 1F90=8080, 2CAE=11438? use real.
    # 0100007F=127.0.0.1, 00000000=0.0.0.0 ; ports hex: 11434=0x2CAA, 443=0x01BB, 6380=0x18EC
    File.write("#{dir}/1/net/tcp", <<~TCP)
      sl local_address rem_address st
      0: 0100007F:0050 00000000:0000 0A
      1: 00000000:2CAA 00000000:0000 0A
      2: 00000000:01BB 00000000:0000 0A
      3: 00000000:18EC 00000000:0000 0A
      4: 00000000:270F 00000000:0000 01
    TCP
    File.write("#{dir}/1/net/tcp6", "sl local_address rem_address st\n")

    a = SecurityAudit.new(proc_path: dir)
    f = a.findings
    raise "loopback leaked"     if f.any? { |x| x.port == 80 }       # 127.0.0.1:80 excluded
    raise "non-LISTEN leaked"   if f.any? { |x| x.port == 0x270F }   # st=01 excluded
    raise "ollama not critical" unless f.find { |x| x.port == 11434 }&.severity == :critical
    raise "443 not ok"          unless f.find { |x| x.port == 443 }&.severity == :ok
    raise "6380 not critical"   unless f.find { |x| x.port == 6380 }&.severity == :critical
    raise "score wrong"         unless a.score == 100 - 20 - 20 # two sensitive

    missing = SecurityAudit.new(proc_path: dir, security_path: "#{dir}/nope.json")
    raise "host_state should be nil when file missing" unless missing.host_state.nil?

    File.write("#{dir}/state.json", '{"collected_at":"now","fail2ban":{"running":true}}')
    present = SecurityAudit.new(proc_path: dir, security_path: "#{dir}/state.json")
    raise "host_state should parse JSON" unless present.host_state[:fail2ban][:running] == true

    missing_cd = SecurityAudit.new(proc_path: dir, container_diff_path: "#{dir}/nope.json")
    raise "container_diff should be nil when file missing" unless missing_cd.container_diff.nil?

    File.write("#{dir}/container-diff.json", '{"collected_at":"now","containers":[{"name":"x","critical":[{"type":"C","path":"/etc/passwd"}]}]}')
    present_cd = SecurityAudit.new(proc_path: dir, container_diff_path: "#{dir}/container-diff.json")
    raise "container_diff should parse JSON" unless present_cd.container_diff[:containers].first[:critical].first[:path] == "/etc/passwd"

    puts "ok — #{f.size} findings, score #{a.score}, summary #{a.summary}"
  end
end
