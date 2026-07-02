module RequireKubernetes
  extend ActiveSupport::Concern

  included do
    before_action :require_kubernetes_environment
    before_action :set_current_namespace
    helper_method :current_kube_client, :current_namespace
  end

  private

  def require_kubernetes_environment
    unless active_environment&.kubernetes?
      redirect_to root_path, alert: "This environment is not Kubernetes."
    end
  end

  def current_kube_client
    @current_kube_client ||= active_environment.kube_client
  end

  def current_namespace
    @namespace ||= params[:ns].presence || "default"
  end

  def set_current_namespace
    @namespace = current_namespace
  end

  # For the namespace-selector dropdown — cheap enough to call from any
  # index action; not called on member actions (scale/logs/delete/...) that
  # don't render the picker.
  def load_namespaces
    @namespaces = current_kube_client.namespaces.map { |n| n.dig("metadata", "name") }
  rescue KubeClient::Error
    @namespaces = [@namespace]
  end
end
