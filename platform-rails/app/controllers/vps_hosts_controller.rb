class VpsHostsController < ApplicationController
  before_action :set_host, only: %i[edit update destroy]

  def index
    @hosts = VpsHost.by_name.includes(:shared_credential)
    @hosts = @hosts.where("name LIKE ? OR hostname LIKE ?", "%#{params[:q]}%", "%#{params[:q]}%") if params[:q].present?
  end

  def new
    @host = VpsHost.new(port: 22, auth_method: "password")
  end

  def create
    @host = VpsHost.new(host_params)
    if @host.save
      AuditLog.record(user: Current.user, action: "vps_host.created", target_type: "VpsHost", target_id: @host.id,
                       metadata: { name: @host.name, hostname: @host.hostname })
      redirect_to vps_hosts_path, notice: "Host adicionado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @host.update(host_params)
      AuditLog.record(user: Current.user, action: "vps_host.updated", target_type: "VpsHost", target_id: @host.id)
      redirect_to vps_hosts_path, notice: "Host atualizado."
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
end
