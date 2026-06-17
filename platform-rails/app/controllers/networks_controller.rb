class NetworksController < ApplicationController
  PROTECTED_NETWORKS = %w[bridge host none].freeze
  SYSTEM_NETWORKS    = %w[bridge host none docker_gwbridge ingress].freeze
  before_action :require_operator!, only: %i[remove create]

  def index
  end

  def rows
    raw_nets = nil; raw_conts = nil; info = nil

    t1 = Thread.new { raw_nets  = current_docker_client.networks             rescue [] }
    t2 = Thread.new { raw_conts = current_docker_client.containers(all: false) rescue [] }
    t3 = Thread.new { info      = current_docker_client.info                 rescue {} }
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
    render layout: false
  rescue => e
    @networks = []
    render layout: false
  end

  def show
    redirect_to networks_path
  end

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

  public

  def remove
    network = current_docker_client.networks.find { |n| n["Id"] == params[:id] }
    if PROTECTED_NETWORKS.include?(network&.dig("Name"))
      redirect_to networks_path, alert: "Cannot remove built-in network."
      return
    end
    current_docker_client.network_remove(params[:id])
    redirect_to networks_path, notice: "Network removed."
  rescue => e
    redirect_to networks_path, alert: "Error: #{e.message}"
  end
end
