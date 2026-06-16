module Ambiente
  class PoliciesController < ApplicationController
    before_action :require_admin!

    def index
      @environments = Environment.all.order(:name)
    end

    def edit
      @environment = Environment.find(params[:id])
    end

    def update
      @environment = Environment.find(params[:id])
      allowed = params.fetch(:environment, {}).permit(:allow_bind_mounts, :allow_privileged, :allow_host_networking, :allow_container_capabilities)
      allowed.each do |k, v|
        AppSetting.set("env_policy_#{@environment.id}_#{k}", v == "1" ? "true" : "false")
      end
      redirect_to ambiente_policies_path, notice: "Políticas atualizadas."
    end

    def self.policy_for(env_id, key)
      AppSetting.get("env_policy_#{env_id}_#{key}", default: "true") == "true"
    end
  end
end
