class SeaweedfsController < ApplicationController
  before_action :require_admin

  def index
    @config   = SeaweedfsService.load_config
    @buckets  = SeaweedfsService.list_buckets
    @tab      = params[:tab] || "identities"
  end

  def create_identity
    config = SeaweedfsService.load_config
    name   = params[:name].to_s.strip
    access = params[:access_key].to_s.strip
    secret = params[:secret_key].to_s.strip
    actions = params[:actions] || ["Read", "Write", "List", "Tagging"]

    if name.blank? || access.blank? || secret.blank?
      flash[:alert] = "Preencha todos os campos obrigatórios (Nome, Access Key, Secret Key)."
      redirect_to seaweedfs_path(tab: "identities") and return
    end

    config["identities"] ||= []
    config["identities"] << {
      "name" => name,
      "credentials" => [
        {
          "accessKey" => access,
          "secretKey" => secret
        }
      ],
      "actions" => actions
    }

    if SeaweedfsService.save_config(config)
      flash[:notice] = "Identidade S3 '#{name}' criada com sucesso e serviço recarregado."
    else
      flash[:alert] = "Erro ao salvar configuração do SeaweedFS."
    end

    redirect_to seaweedfs_path(tab: "identities")
  end

  def destroy_identity
    config = SeaweedfsService.load_config
    name   = params[:name].to_s

    if config["identities"].is_a?(Array)
      config["identities"].reject! { |i| i["name"] == name }
      SeaweedfsService.save_config(config)
      flash[:notice] = "Identidade S3 '#{name}' removida com sucesso."
    end

    redirect_to seaweedfs_path(tab: "identities")
  end

  private

  def require_admin
    redirect_to root_path, alert: "Acesso restrito a administradores." unless Current.user&.admin?
  end
end
