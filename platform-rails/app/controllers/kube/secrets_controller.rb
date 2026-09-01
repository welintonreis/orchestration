module Kube
  class SecretsController < ApplicationController
    include RequireKubernetes

    def index
    end

    def rows
      load_namespaces
      @secrets = current_kube_client.secrets(ns: @namespace)
    rescue KubeClient::Error => e
      @secrets = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end

    def destroy
      current_kube_client.delete_secret(ns: @namespace, name: params[:name])
      redirect_to kube_secrets_path(ns: @namespace), notice: "Secret #{params[:name]} deleted."
    rescue KubeClient::Error => e
      redirect_to kube_secrets_path(ns: @namespace), alert: "Error: #{e.message}"
    end
  end
end
