require "timeout"

module Kube
  # Single-pane-of-glass across every registered cluster — deliberately NOT
  # scoped to the active environment (RequireKubernetes doesn't apply here;
  # this is the one screen meant to span all of them at once).
  class FleetController < ApplicationController
    PROBE_TIMEOUT = 5 # seconds — one slow/offline cluster must not stall the rest

    # Shell only: the cluster list is one AR query, enough for the empty state
    # and for sizing the skeleton. The probing (4 API calls per cluster, and up
    # to PROBE_TIMEOUT seconds when one is offline) happens in #rows.
    def index
      @environments = kube_environments
    end

    def rows
      @rows = kube_environments.map { |env| Thread.new { fleet_row(env) } }.map(&:value)
    end

    private

    def kube_environments
      Environment.where(endpoint_type: "kubernetes").order(:name).to_a
    end

    def fleet_row(env)
      Timeout.timeout(PROBE_TIMEOUT) do
        client      = env.kube_client
        version     = client.version
        nodes       = client.nodes
        pods        = client.all_pods
        deployments = client.all_deployments

        nodes_ready = nodes.count { |n| node_ready?(n) }
        pods_failed = pods.count { |p| p.dig("status", "phase") == "Failed" }
        deployments_degraded = deployments.count { |d| degraded?(d) }

        {
          environment: env, online: true,
          version: version["gitVersion"] || version["Major"] && "#{version['major']}.#{version['minor']}",
          nodes_ready: nodes_ready, nodes_total: nodes.size,
          pods_failed: pods_failed, deployments_degraded: deployments_degraded
        }
      end
    rescue => e
      { environment: env, online: false, error: e.message }
    end

    def node_ready?(node)
      node.dig("status", "conditions")&.find { |c| c["type"] == "Ready" }&.dig("status") == "True"
    end

    def degraded?(deployment)
      desired = deployment.dig("spec", "replicas").to_i
      ready   = deployment.dig("status", "readyReplicas").to_i
      desired > 0 && ready < desired
    end
  end
end
