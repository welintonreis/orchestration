module Ambiente
  class LicensesController < ApplicationController

    def index
      @info = current_docker_client.info rescue {}
      @license = {
        product: "RedHusky Platform",
        plan: AppSetting.get("license_plan", default: "Community"),
        expires: AppSetting.get("license_expires", default: "Sem expiração"),
        seats: AppSetting.get("license_seats", default: "Ilimitado"),
        issued_to: AppSetting.get("license_issued_to", default: "—"),
        docker_version: @info.dig("ServerVersion") || "—",
        nodes_used: @info.dig("Swarm", "Nodes") || 1,
        nodes_max: AppSetting.get("license_nodes_max", default: "Ilimitado"),
      }
    end
  end
end
