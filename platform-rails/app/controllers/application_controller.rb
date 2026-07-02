class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  prepend_before_action :check_setup

  helper_method :current_docker_client, :active_environment, :runtime_capabilities

  private

  # Nav visibility: Podman capability is cheap to check (cached 10min) and
  # tolerant of a down/unreachable daemon — never raises, worst case shows
  # the swarm-only nav items on an environment that'll redirect on click.
  def runtime_capabilities
    @runtime_capabilities ||= current_docker_client.capabilities
  rescue DockerClient::Error
    { swarm: true, compose: true, pods: false }
  end

  def check_setup
    redirect_to setup_path unless User.any?
  end

  def active_environment
    @active_environment ||= begin
      env_id = cookies[:active_env]
      if env_id.present?
        Environment.find_by(id: env_id) || Environment.active_env
      else
        Environment.active_env
      end
    end
  end

  def current_docker_client
    @current_docker_client ||= DockerClient.new(endpoint: docker_endpoint)
  end

  # A fresh DockerClient — one Excon connection isn't safe to share across
  # threads, so any code firing concurrent Docker calls (rows actions that
  # Thread.new multiple requests) must give each thread its own client
  # built from this rather than reusing current_docker_client.
  def docker_endpoint
    active_environment&.effective_endpoint || "unix:///var/run/docker.sock"
  end
end
