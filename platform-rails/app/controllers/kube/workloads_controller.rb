module Kube
  class WorkloadsController < ApplicationController
    include RequireKubernetes

    # Shell only — RequireKubernetes still redirects a non-k8s environment
    # here, before any skeleton paints. The API calls live in #rows.
    def index
    end

    def rows
      load_namespaces
      @deployments  = current_kube_client.deployments(ns: @namespace)
      @statefulsets = current_kube_client.statefulsets(ns: @namespace)
      @daemonsets   = current_kube_client.daemonsets(ns: @namespace)
    rescue KubeClient::Error => e
      @deployments = @statefulsets = @daemonsets = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end

    def scale
      current_kube_client.scale(params[:kind], params[:name], ns: @namespace, replicas: params[:replicas].to_i)
      redirect_to kube_workloads_path(ns: @namespace), notice: "Scaled #{params[:name]} to #{params[:replicas]}."
    rescue KubeClient::Error => e
      redirect_to kube_workloads_path(ns: @namespace), alert: "Error: #{e.message}"
    end

    def restart
      current_kube_client.restart_workload(params[:kind], params[:name], ns: @namespace)
      redirect_to kube_workloads_path(ns: @namespace), notice: "Restarting #{params[:name]}."
    rescue KubeClient::Error => e
      redirect_to kube_workloads_path(ns: @namespace), alert: "Error: #{e.message}"
    end

    def destroy
      current_kube_client.delete_workload(params[:kind], params[:name], ns: @namespace)
      redirect_to kube_workloads_path(ns: @namespace), notice: "Deleted #{params[:name]}."
    rescue KubeClient::Error => e
      redirect_to kube_workloads_path(ns: @namespace), alert: "Error: #{e.message}"
    end
  end
end
