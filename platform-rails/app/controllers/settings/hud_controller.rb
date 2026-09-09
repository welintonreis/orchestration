module Settings
  # Dispositivos autorizados a ler a orelhinha (redhusky-hud). Mesmo desenho da
  # tela Edge: o token aparece UMA vez, no flash, e o que fica no banco é só o
  # digest.
  class HudController < ApplicationController
    def index
      @devices = HudDevice.order(:name)
      @endpoint = "#{request.base_url}/internal/hud"
    end

    def create
      name = params[:device_name].to_s.strip
      if name.blank?
        redirect_to settings_hud_path, alert: "Nome do dispositivo é obrigatório."
        return
      end

      _device, raw = HudDevice.issue!(name: name)
      # Config pronto para colar: quem instala o HUD não deveria ter de montar
      # JSON à mão para descobrir o nome dos campos.
      flash[:hud_config] = JSON.pretty_generate(
        "notch_y" => 0.5, "interval_secs" => 15, "ui_scale" => 0.75,
        "sources" => [ { "id" => "orchestration",
                         "url" => "#{request.base_url}/internal/hud",
                         "token" => raw,
                         "portal_url" => request.base_url } ]
      )
      redirect_to settings_hud_path
    end

    def revoke
      device = HudDevice.find(params[:id])
      device.revoke!
      redirect_to settings_hud_path, notice: "Dispositivo \"#{device.name}\" revogado."
    end
  end
end
