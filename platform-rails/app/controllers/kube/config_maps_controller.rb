module Kube
  class ConfigMapsController < ApplicationController
    include RequireKubernetes

    def index
    end

    def rows
      load_namespaces
      @config_maps = current_kube_client.config_maps(ns: @namespace)
    rescue KubeClient::Error => e
      @config_maps = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end

    def destroy
      current_kube_client.delete_config_map(ns: @namespace, name: params[:name])
      redirect_to kube_config_maps_path(ns: @namespace), notice: "ConfigMap #{params[:name]} deleted."
    rescue KubeClient::Error => e
      redirect_to kube_config_maps_path(ns: @namespace), alert: "Error: #{e.message}"
    end
  end
end
