module Kube
  class NodesController < ApplicationController
    include RequireKubernetes

    # Shell only — RequireKubernetes still redirects a non-k8s environment
    # here, before any skeleton paints. The API calls live in #rows.
    def index
    end

    def rows
      @nodes = current_kube_client.nodes
      @top_pods = current_kube_client.top_pods(ns: "kube-system") # cheap presence probe for metrics-server
    rescue KubeClient::Error => e
      @nodes = []
      @top_pods = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end
  end
end
