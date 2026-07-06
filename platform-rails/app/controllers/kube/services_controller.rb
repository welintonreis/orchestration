module Kube
  class ServicesController < ApplicationController
    include RequireKubernetes

    def index
      load_namespaces
      @services = current_kube_client.services(ns: @namespace)
    rescue KubeClient::Error => e
      @services = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end

    def destroy
      current_kube_client.delete_service(ns: @namespace, name: params[:name])
      redirect_to kube_services_path(ns: @namespace), notice: "Service #{params[:name]} deleted."
    rescue KubeClient::Error => e
      redirect_to kube_services_path(ns: @namespace), alert: "Error: #{e.message}"
    end
  end
end
