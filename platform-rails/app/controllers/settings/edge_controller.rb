module Settings
  class EdgeController < ApplicationController

    def index
      @edge_key     = EdgeEnrollmentToken.edge_key
      @edge_enabled = AppSetting.get("edge_enabled", default: "false") == "true"
      @nodes        = EdgeNode.order(:name)
    end

    def update
      p = params.permit(:edge_enabled, :edge_polling_interval)
      AppSetting.set("edge_enabled", p[:edge_enabled] == "1" ? "true" : "false")
      AppSetting.set("edge_polling_interval", p[:edge_polling_interval]) if p[:edge_polling_interval].present?
      redirect_to settings_edge_path, notice: "Configurações Edge salvas."
    end

    def regenerate_key
      AppSetting.set("edge_key", SecureRandom.hex(32))
      redirect_to settings_edge_path, notice: "Chave Edge regenerada. Enrollment tokens já emitidos deixam de funcionar."
    end

    # Shows the one-liner exactly once (via flash) — same shown-once
    # treatment as a freshly generated node token; nothing sensitive is
    # persisted server-side beyond the signed, short-lived token itself.
    def generate_enrollment
      name = params[:node_name].to_s.strip
      if name.blank?
        redirect_to settings_edge_path, alert: "Nome do node é obrigatório."
        return
      end

      token = EdgeEnrollmentToken.generate(node_name: name)
      flash[:enrollment_command] = <<~SH.strip
        docker run -d --restart=always --name redhusk-edge-agent \\
          -v /var/run/docker.sock:/var/run/docker.sock \\
          -e EDGE_URL=#{request.base_url} \\
          -e EDGE_ENROLLMENT_TOKEN=#{token} \\
          redhusk/orchestration-agent:v0.1.0
      SH
      redirect_to settings_edge_path
    end

    def revoke_node
      node = EdgeNode.find(params[:id])
      node.revoke!
      redirect_to settings_edge_path, notice: "Node \"#{node.name}\" revogado."
    end
  end
end
