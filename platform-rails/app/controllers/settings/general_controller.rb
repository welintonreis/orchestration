module Settings
  class GeneralController < ApplicationController
    before_action :require_admin!

    def index
      @info = current_docker_client.info rescue {}
      @settings = {
        app_name:          AppSetting.get("app_name",          default: "RedHusky"),
        app_url:           AppSetting.get("app_url",           default: request.base_url),
        logo_url:          AppSetting.get("logo_url",          default: ""),
        enable_analytics:  AppSetting.get("enable_analytics",  default: "false") == "true",
        alert_webhook_url: AppSetting.get("alert_webhook_url", default: ""),
      }
    end

    def update
      p = params.permit(:app_name, :app_url, :logo_url, :enable_analytics, :alert_webhook_url)
      p.each do |k, v|
        AppSetting.set(k, v)
      end
      redirect_to settings_general_path, notice: "Configurações salvas."
    end
  end
end
