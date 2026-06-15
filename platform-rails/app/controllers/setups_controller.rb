class SetupsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :check_setup

  before_action :redirect_if_setup

  def show
    @user = User.new
  end

  def create
    @user = User.new(setup_params.except(:password_confirmation))

    if setup_params[:password] != setup_params[:password_confirmation]
      @user.errors.add(:password_confirmation, "doesn't match password")
      render :show, status: :unprocessable_entity and return
    end

    ActiveRecord::Base.transaction do
      @user.save!
      Environment.create!(
        name: "local",
        endpoint: "unix:///var/run/docker.sock",
        endpoint_type: "unix",
        active: true
      )
    end

    start_new_session_for(@user)
    redirect_to root_path, notice: "Welcome! Your account and local environment have been configured."
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_entity
  end

  private

  def redirect_if_setup
    redirect_to root_path if User.any?
  end

  def setup_params
    params.permit(:email_address, :password, :password_confirmation)
  end
end
