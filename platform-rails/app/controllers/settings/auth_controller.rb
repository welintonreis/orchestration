module Settings
  class AuthController < ApplicationController
    before_action :require_admin!

    def index
      @settings = {
        session_timeout:      AppSetting.get("auth_session_timeout",      default: "480"),
        require_2fa:          AppSetting.get("auth_require_2fa",          default: "false") == "true",
        min_password_length:  AppSetting.get("auth_min_password_length",  default: "12"),
        password_expires_days: AppSetting.get("auth_password_expires_days", default: "0"),
        allow_registration:   AppSetting.get("auth_allow_registration",   default: "false") == "true",
      }
      @total_users   = User.count
      @active_users  = User.active_users.count
      @admin_count   = User.where(role: "admin").count
    end

    def update
      p = params.permit(:session_timeout, :require_2fa, :min_password_length, :password_expires_days, :allow_registration)
      p.each do |k, v|
        AppSetting.set("auth_#{k}", v)
      end
      redirect_to settings_auth_path, notice: "Configurações de autenticação salvas."
    end
  end
end
