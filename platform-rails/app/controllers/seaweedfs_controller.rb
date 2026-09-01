class SeaweedfsController < ApplicationController
  before_action :require_admin

  # Bucket and prefix links inside rows.html.erb point back at this action so
  # the URL keeps the selected bucket — when that arrives as a frame
  # navigation, render the rows directly (see ContainersController#index for
  # why nesting a frame inside the frame being renavigated silently stalls).
  def index
    rows if turbo_frame_request?
  end

  def rows
    @config   = SeaweedfsService.load_config
    @buckets  = SeaweedfsService.list_buckets
    @tab      = params[:tab] || "buckets"
    @selected_bucket = params[:bucket] || @buckets.first
    @prefix   = params[:prefix].to_s

    if @selected_bucket.present?
      @objects_data = SeaweedfsService.list_objects(@selected_bucket, @prefix)
    else
      @objects_data = { "Entries" => [] }
    end

    render "rows", layout: false
  end

  def create_bucket
    name = params[:bucket_name].to_s.strip
    if name.present? && SeaweedfsService.create_bucket(name)
      flash[:notice] = "Bucket '#{name}' criado com sucesso."
    else
      flash[:alert] = "Erro ao criar bucket '#{name}'."
    end
    redirect_to seaweedfs_path(tab: "buckets", bucket: name)
  end

  def upload_file
    bucket = params[:bucket].to_s.strip
    prefix = params[:prefix].to_s.strip
    file   = params[:file]

    if bucket.present? && file.present?
      if SeaweedfsService.upload_file(bucket, prefix, file)
        flash[:notice] = "Arquivo '#{file.original_filename}' enviado com sucesso."
      else
        flash[:alert] = "Erro ao enviar arquivo para o bucket."
      end
    else
      flash[:alert] = "Selecione um arquivo."
    end
    redirect_to seaweedfs_path(tab: "buckets", bucket: bucket, prefix: prefix)
  end

  def download_object
    bucket = params[:bucket].to_s.strip
    path   = params[:path].to_s.strip

    res = SeaweedfsService.get_object(bucket, path)
    if res && res.is_a?(Net::HTTPSuccess)
      filename = path.split("/").last
      send_data res.body, filename: filename, type: res.content_type || "application/octet-stream", disposition: "inline"
    else
      redirect_to seaweedfs_path(tab: "buckets", bucket: bucket), alert: "Arquivo não encontrado ou erro na leitura."
    end
  end

  def destroy_object
    bucket = params[:bucket].to_s.strip
    path   = params[:path].to_s.strip
    prefix = params[:prefix].to_s.strip

    if bucket.present? && path.present?
      if SeaweedfsService.delete_object(bucket, path)
        flash[:notice] = "Item '#{path}' removido com sucesso."
      else
        flash[:alert] = "Erro ao remover item."
      end
    end
    redirect_to seaweedfs_path(tab: "buckets", bucket: bucket, prefix: prefix)
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
