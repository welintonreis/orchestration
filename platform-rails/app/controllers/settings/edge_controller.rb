module Settings
  class EdgeController < ApplicationController
    before_action :require_admin!

    def index
      @info = current_docker_client.info rescue {}
      @edge_key = AppSetting.get("edge_key", default: SecureRandom.hex(32))
      AppSetting.set("edge_key", @edge_key) if AppSetting.get("edge_key").nil?
      @edge_enabled = AppSetting.get("edge_enabled", default: "false") == "true"
      @edge_nodes = AppSetting.get("edge_node_count", default: "0").to_i
    end

    def update
      p = params.permit(:edge_enabled, :edge_polling_interval)
      AppSetting.set("edge_enabled", p[:edge_enabled] == "1" ? "true" : "false")
      AppSetting.set("edge_polling_interval", p[:edge_polling_interval]) if p[:edge_polling_interval].present?
      redirect_to settings_edge_path, notice: "Configurações Edge salvas."
    end

    def regenerate_key
      AppSetting.set("edge_key", SecureRandom.hex(32))
      redirect_to settings_edge_path, notice: "Chave Edge regenerada."
    end
  end
end
