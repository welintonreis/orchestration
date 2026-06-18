class NetworksController < ApplicationController
  PROTECTED_NETWORKS = %w[bridge host none].freeze
  SYSTEM_NETWORKS    = %w[bridge host none docker_gwbridge ingress].freeze
  before_action :require_operator!, only: %i[remove create]

  # create/remove redirect back here from inside the lazy turbo-frame
  # (networks-content) — same self-referential nested-frame bug fixed for
  # ContainersController et al.
  def index
    rows if turbo_frame_request?
  end

  def rows
    raw_nets = nil; raw_conts = nil; info = nil
    endpoint = docker_endpoint

    t1 = Thread.new { raw_nets  = DockerClient.new(endpoint: endpoint).networks             rescue [] }
    t2 = Thread.new { raw_conts = DockerClient.new(endpoint: endpoint).containers(all: false) rescue [] }
    t3 = Thread.new { info      = DockerClient.new(endpoint: endpoint).info                 rescue {} }
    t1.join; t2.join; t3.join

    @node_name = info["Name"] || "—"

    net_containers = {}
    raw_conts.each do |c|
      cname = c["Names"]&.first&.sub(/^\//, "") || c["Id"][0..11]
      (c.dig("NetworkSettings", "Networks") || {}).each do |net_name, ninfo|
        net_containers[net_name] ||= []
        net_containers[net_name] << {
          "Name"        => cname,
          "Id"          => c["Id"],
          "IPv4Address" => ninfo["IPAddress"].presence || "—",
          "IPv6Address" => ninfo["GlobalIPv6Address"].presence || "—",
          "MacAddress"  => ninfo["MacAddress"].presence || "—",
          "EndpointID"  => ninfo["EndpointID"].to_s
        }
      end
    end

    @networks = raw_nets.map { |n| enrich_network(n).merge("_containers" => net_containers[n["Name"]] || []) }
    render "rows", layout: false
  rescue => e
    @networks = []
    render "rows", layout: false
  end

  def show
    redirect_to networks_path
  end

  # create's form posts with data-turbo="false" (a plain full-page submit,
  # not a turbo-frame navigation) since it's a modal whose result should
  # replace the whole page — turbo_frame_request? is false here, so the
  # plain redirect_to is correct as-is and doesn't have the swallowed-flash
  # bug described above for remove.
  def create
    name    = params[:name].to_s.strip
    driver  = params[:driver].presence || "bridge"
    subnet  = params[:subnet].presence
    gateway = params[:gateway].presence
    attach  = params[:attachable] == "1"
    current_docker_client.network_create(name: name, driver: driver, attachable: attach, subnet: subnet, gateway: gateway)
    redirect_to networks_path, notice: "Rede \"#{name}\" criada."
  rescue => e
    redirect_to networks_path, alert: "Erro ao criar rede: #{e.message}"
  end

  # Triggered by the remove button living inside the networks-content
  # turbo-frame, which redirects back to this same index — a Turbo-Frame
  # redirect to #index renders "rows" with layout: false (see above), so
  # shared/_flash (only rendered by the full layout) never displays the
  # notice/alert and Rails never sweeps it from the session: the message
  # silently survives into the next unrelated full-page navigation. Render
  # rows directly instead, using flash.now so this same response shows it.
  def remove
    network = current_docker_client.networks.find { |n| n["Id"] == params[:id] }
    if PROTECTED_NETWORKS.include?(network&.dig("Name"))
      return render_networks_flash(alert: "Cannot remove built-in network.")
    end
    current_docker_client.network_remove(params[:id])
    render_networks_flash(notice: "Network removed.")
  rescue => e
    render_networks_flash(alert: "Error: #{e.message}")
  end

  private

  def enrich_network(n)
    name = n["Name"]
    stack = n.dig("Labels", "com.docker.stack.namespace") ||
            n.dig("Labels", "com.docker.compose.project") ||
            (name.include?("_") && !SYSTEM_NETWORKS.include?(name) ? name.split("_").first : nil)
    ipam_configs = n.dig("IPAM", "Config") || []
    ipv4 = ipam_configs.find { |c| c["Subnet"]&.include?(".") } || {}
    ipv6 = ipam_configs.find { |c| c["Subnet"]&.include?(":") } || {}
    ownership = SYSTEM_NETWORKS.include?(name) ? "public" : "administrators"
    n.merge(
      "_stack"     => stack,
      "_ipv4"      => ipv4,
      "_ipv6"      => ipv6,
      "_ownership" => ownership,
      "_protected" => PROTECTED_NETWORKS.include?(name)
    )
  end

  def render_networks_flash(notice: nil, alert: nil)
    if turbo_frame_request?
      flash.now[:notice] = notice if notice
      flash.now[:alert]  = alert  if alert
      rows
    else
      redirect_to networks_path, notice: notice, alert: alert
    end
  end
end
