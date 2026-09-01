module Swarm
  class PoliciesController < ApplicationController
    include SwarmGuard

    def index
    end

    def rows
      services = current_docker_client.services
      @placement_rules = services.flat_map do |svc|
        constraints = svc.dig("Spec", "TaskTemplate", "Placement", "Constraints") || []
        prefs       = svc.dig("Spec", "TaskTemplate", "Placement", "Preferences") || []
        constraints.map { |c| { service: svc.dig("Spec", "Name"), type: "Constraint", rule: c } } +
          prefs.map { |p| { service: svc.dig("Spec", "Name"), type: "Preference", rule: p.to_s } }
      end
      @nodes = current_docker_client.nodes
      @node_labels = @nodes.flat_map { |n| (n.dig("Spec", "Labels") || {}).keys }.uniq.sort
    rescue => e
      @placement_rules = []
      @nodes = []
      @node_labels = []
      flash.now[:alert] = "Erro Swarm: #{e.message}"
    end
  end
end
