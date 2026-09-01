class VpsHostsController < ApplicationController
  before_action :set_host, only: %i[edit update destroy]

  def index
    @hosts = VpsHost.by_name.includes(:shared_credential)
    @hosts = @hosts.where("name LIKE ? OR hostname LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
  end

  def new
    @host = VpsHost.new(port: 22, auth_method: "key")
  end

  def create
    @host = VpsHost.new(host_params)
    assign_inline_credential! if inline_credential_present?

    if @host.save
      AuditLog.record(user: Current.user, action: "vps_host.created", target_type: "VpsHost", target_id: @host.id,
                       metadata: { name: @host.name, hostname: @host.hostname })
      redirect_to vps_hosts_path, notice: "Host '#{@host.name}' adicionado com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @host.assign_attributes(host_params)
    assign_inline_credential! if inline_credential_present?

    if @host.save
      AuditLog.record(user: Current.user, action: "vps_host.updated", target_type: "VpsHost", target_id: @host.id)
      redirect_to vps_hosts_path, notice: "Host '#{@host.name}' atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @host.name
    @host.destroy
    AuditLog.record(user: Current.user, action: "vps_host.deleted", target_type: "VpsHost", target_id: nil,
                     metadata: { name: name })
    redirect_to vps_hosts_path, notice: "Host removido."
  end

  private

  def set_host
    @host = VpsHost.find(params[:id])
  end

  def host_params
    params.require(:vps_host).permit(:name, :hostname, :port, :username, :auth_method, :description, :shared_credential_id)
  end

  def inline_credential_present?
    params[:direct_secret].present?
  end

  def assign_inline_credential!
    type = @host.auth_method == "password" ? "password" : "ssh_key"
    cred_name = "#{@host.name} (#{type == 'ssh_key' ? 'SSH Key' : 'Senha'})"
    cred = SharedCredential.find_or_initialize_by(name: cred_name)
    cred.credential_type = type
    cred.username = @host.username.presence || "root"
    cred.encrypted_secret = params[:direct_secret].to_s.strip
    cred.description = "Criada automaticamente para o host #{@host.name}"
    cred.save!
    @host.shared_credential = cred
  end
end
