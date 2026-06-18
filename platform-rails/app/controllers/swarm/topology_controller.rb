module Swarm
  # Nodes → stacks → services → containers (tasks, including dead ones)
  # scheduled on each node — a single read-only view of the whole swarm's
  # shape, since piecing that together today means cross-referencing
  # /swarm/nodes, /swarm/services and each service's task list by hand.
  class TopologyController < ApplicationController
    include SwarmGuard

    def index
      client   = current_docker_client
      @nodes   = client.nodes rescue []
      services = client.services rescue []
      tasks    = client.tasks rescue []

      services_by_id = services.index_by { |s| s["ID"] }
      tasks_by_node  = tasks.group_by { |t| t["NodeID"] }

      @topology = @nodes.map do |node|
        node_tasks = tasks_by_node[node["ID"]] || []

        stacks = node_tasks
          .group_by { |t| services_by_id.dig(t["ServiceID"], "Spec", "Labels", "com.docker.stack.namespace") }
          .map do |stack_name, stack_tasks|
            services_in_stack = stack_tasks
              .group_by { |t| t["ServiceID"] }
              .map do |service_id, svc_tasks|
                {
                  service: services_by_id[service_id],
                  containers: svc_tasks.sort_by { |t| t.dig("Status", "Timestamp").to_s }.reverse
                }
              end
              .sort_by { |s| s[:service]&.dig("Spec", "Name").to_s }

            { name: stack_name || "(sem stack)", services: services_in_stack }
          end
          .sort_by { |s| s[:name] }

        { node: node, stacks: stacks }
      end
    end
  end
end
