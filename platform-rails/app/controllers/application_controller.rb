class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  prepend_before_action :check_setup

  helper_method :current_docker_client, :active_environment

  private

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
    @current_docker_client ||= begin
      endpoint = active_environment&.endpoint || "unix:///var/run/docker.sock"
      DockerClient.new(endpoint: endpoint)
    end
  end
end
