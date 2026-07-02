module Kube
  class NodesController < ApplicationController
    include RequireKubernetes

    def index
      @nodes = current_kube_client.nodes
      @top_pods = current_kube_client.top_pods(ns: "kube-system") # cheap presence probe for metrics-server
    rescue KubeClient::Error => e
      @nodes = []
      @top_pods = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end
  end
end
