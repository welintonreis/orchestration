require "yaml"
require "json"

# Read-only drift detection for Git Deploy stacks — Argo CD-style sync status.
# Renders the desired compose into a normalized per-service shape, inspects the
# live swarm services for the same stack namespace, and diffs the two. Never
# mutates the swarm; only writes sync_status / health / drift_detail on the
# stack.
#
# Diff is over a curated field set (image, replicas, env, labels). Both sides
# are normalized the same way — digest stripped when the tag matches, generated
# `com.docker.stack.*` labels dropped, env sorted, replicas defaulted — so the
# defaults Swarm injects into `service inspect` don't read as false drift.
class GitDriftService
  FIELDS = %w[image replicas env labels].freeze

  Result = Struct.new(:sync_status, :health, :detail, :normalized, keyword_init: true)

  def self.call(git_stack, repo_path: nil)
    new(git_stack, repo_path: repo_path).run
  end

  def initialize(stack, repo_path: nil)
    @stack     = stack
    @repo_path = repo_path
  end

  def run
    desired = desired_services
    live    = live_services
    detail  = diff(desired, live)
    sync    = detail.empty? ? "synced" : "out_of_sync"
    health  = assess_health(desired)

    @stack.update_columns(
      sync_status:   sync,
      health:        health,
      last_drift_at: Time.current,
      drift_detail:  { services: detail, checked_at: Time.current }.to_json
    )
    Result.new(sync_status: sync, health: health, detail: detail, normalized: desired)
  rescue => e
    @stack.update_columns(
      sync_status: "unknown", health: "unknown", last_drift_at: Time.current,
      drift_detail: { error: e.message }.to_json
    )
    Result.new(sync_status: "unknown", health: "unknown", detail: [], normalized: {})
  end

  # Public so GitDeployer can persist the same normalization as the revision's
  # last-applied state.
  def desired_services
    compose = load_compose
    vars    = env_vars
    (compose["services"] || {}).each_with_object({}) do |(name, svc), acc|
      acc[name] = normalize_desired(svc || {}, vars)
    end
  end

  private

  # ── desired side (compose) ──

  def load_compose
    path = compose_path
    raise "compose file not found: #{@stack.compose_file}" unless path && File.exist?(path)
    YAML.safe_load(File.read(path), aliases: true) || {}
  end

  def compose_path
    base = @repo_path || GitUnpacker.repo_dir(@stack).to_s
    File.join(base, @stack.compose_file)
  end

  def env_vars
    return {} if @stack.env_content.blank?
    @stack.env_content.each_line.each_with_object({}) do |line, h|
      line = line.strip
      next if line.empty? || line.start_with?("#") || !line.include?("=")
      k, v = line.split("=", 2)
      h[k.strip] = v.to_s.strip.gsub(/\A["']|["']\z/, "")
    end
  end

  # Minimal compose interpolation: ${VAR}, ${VAR:-default}, $VAR.
  def interpolate(str, vars)
    return str unless str.is_a?(String)
    str.gsub(/\$\{(\w+)(?::-([^}]*))?\}|\$(\w+)/) do
      key = Regexp.last_match(1) || Regexp.last_match(3)
      vars.fetch(key) { Regexp.last_match(2).to_s }
    end
  end

  def normalize_desired(svc, vars)
    deploy = svc["deploy"] || {}
    {
      "image"    => strip_digest(interpolate(svc["image"].to_s, vars)),
      "replicas" => desired_replicas(deploy),
      "env"      => normalize_env(svc["environment"], vars),
      "labels"   => normalize_labels(merge_label_sources(svc["labels"], deploy["labels"]))
    }
  end

  def desired_replicas(deploy)
    return "global" if deploy["mode"] == "global"
    (deploy["replicas"] || 1).to_i
  end

  def normalize_env(env, vars)
    list = case env
           when Hash  then env.map { |k, v| "#{k}=#{interpolate(v.to_s, vars)}" }
           when Array then env.map { |e| interpolate(e.to_s, vars) }
           else []
           end
    list.sort
  end

  def merge_label_sources(*sources)
    sources.compact.each_with_object({}) do |src, acc|
      pairs = src.is_a?(Hash) ? src.to_a : Array(src).map { |e| e.to_s.split("=", 2) }
      pairs.each { |k, v| acc[k.to_s] = v.to_s }
    end
  end

  # ── live side (swarm) ──

  def client
    @client ||= DockerClient.new(endpoint: @stack.environment.effective_endpoint)
  end

  def live_raw_services
    @live_raw_services ||= client.services.select do |s|
      s.dig("Spec", "Labels", "com.docker.stack.namespace") == @stack.name
    end
  rescue
    @live_raw_services = []
  end

  def live_services
    live_raw_services.each_with_object({}) do |s, acc|
      spec  = s["Spec"] || {}
      full  = spec["Name"].to_s                       # "<namespace>_<service>"
      short = full.sub(/\A#{Regexp.escape(@stack.name)}_/, "")
      cs    = spec.dig("TaskTemplate", "ContainerSpec") || {}
      acc[short] = {
        "image"    => strip_digest(cs["Image"]),
        "replicas" => live_replicas(spec),
        "env"      => Array(cs["Env"]).sort,
        "labels"   => normalize_labels(spec["Labels"])
      }
    end
  end

  def live_replicas(spec)
    return "global" if spec.dig("Mode", "Global")
    (spec.dig("Mode", "Replicated", "Replicas") || 1).to_i
  end

  # ── shared normalization ──

  # Swarm pins `repo:tag@sha256:…` on deploy; compose usually carries just
  # `repo:tag`. Compare on the tag, ignoring the resolved digest.
  def strip_digest(image) = image.to_s.split("@").first

  def normalize_labels(labels)
    (labels || {})
      .reject { |k, _| k.to_s.start_with?("com.docker.stack") }
      .map { |k, v| [k.to_s, v.to_s] }
      .sort
      .to_h
  end

  # ── diff + health ──

  def diff(desired, live)
    (desired.keys | live.keys).sort.each_with_object([]) do |name, acc|
      d = desired[name]
      l = live[name]
      if d.nil?
        acc << { "service" => name, "state" => "extra", "fields" => {} }    # in swarm, absent from git
      elsif l.nil?
        acc << { "service" => name, "state" => "missing", "fields" => {} }  # in git, not deployed
      else
        fields = FIELDS.each_with_object({}) do |f, h|
          h[f] = { "desired" => d[f], "live" => l[f] } if d[f] != l[f]
        end
        acc << { "service" => name, "state" => "drift", "fields" => fields } if fields.any?
      end
    end
  end

  def assess_health(desired)
    return "missing" if desired.any? && live_raw_services.empty?
    return "unknown" if live_raw_services.empty?

    states = live_raw_services.map { |s| service_health(s) }
    return "degraded"    if states.include?("degraded")
    return "progressing" if states.include?("progressing")
    "healthy"
  end

  def service_health(s)
    spec = s["Spec"] || {}
    want = live_replicas(spec)
    return "healthy" if want == "global"

    tasks   = (client.service_tasks(s["ID"]) rescue [])
    running = tasks.count { |t| t.dig("Status", "State") == "running" }
    if want.to_i.positive? && running >= want.to_i then "healthy"
    elsif running.zero? then "degraded"
    else "progressing"
    end
  end
end
