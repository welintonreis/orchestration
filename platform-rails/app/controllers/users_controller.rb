class UsersController < ApplicationController
  before_action :require_admin!
  before_action :set_user, only: %i[edit update destroy toggle_active]

  def index
    @users = User.order(:email_address)
  end

  def new
    @user = User.new(role: "readonly")
  end

  def create
    @user = User.new(user_params)
    if @user.save
      AuditLog.record(user: Current.user, action: "create_user",
                      target_type: "User", target_id: @user.id,
                      metadata: { email: @user.email_address, role: @user.role },
                      ip_address: request.remote_ip)
      redirect_to users_path, notice: "User #{@user.email_address} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params_update)
      AuditLog.record(user: Current.user, action: "update_user",
                      target_type: "User", target_id: @user.id,
                      metadata: { email: @user.email_address, role: @user.role },
                      ip_address: request.remote_ip)
      redirect_to users_path, notice: "User #{@user.email_address} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == Current.user
      redirect_to users_path, alert: "Cannot delete your own account."
      return
    end
    email = @user.email_address
    @user.destroy
    AuditLog.record(user: Current.user, action: "delete_user",
                    target_type: "User", target_id: @user.id,
                    metadata: { email: email },
                    ip_address: request.remote_ip)
    redirect_to users_path, notice: "User #{email} deleted."
  end

  def toggle_active
    @user.update!(active: !@user.active)
    state = @user.active? ? "activated" : "deactivated"
    AuditLog.record(user: Current.user, action: "#{state}_user",
                    target_type: "User", target_id: @user.id,
                    metadata: { email: @user.email_address },
                    ip_address: request.remote_ip)
    redirect_to users_path, notice: "User #{@user.email_address} #{state}."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :role)
  end

  def user_params_update
    p = params.require(:user).permit(:email_address, :role, :password, :password_confirmation)
    p.delete(:password) if p[:password].blank?
    p.delete(:password_confirmation) if p[:password_confirmation].blank?
    p
  end
end
