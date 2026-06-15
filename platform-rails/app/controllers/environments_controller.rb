class EnvironmentsController < ApplicationController
  before_action :set_environment, only: %i[destroy activate]

  def index
    @environments = Environment.order(:name)
    @reachable = {}
    @environments.each do |env|
      begin
        DockerClient.new(endpoint: env.endpoint).info
        @reachable[env.id] = true
      rescue => _e
        @reachable[env.id] = false
      end
    end
  end

  def new
    @environment = Environment.new
  end

  def create
    @environment = Environment.new(environment_params)
    if @environment.save
      # Test connectivity after saving — warn but don't block
      begin
        DockerClient.new(endpoint: @environment.endpoint).info
        flash[:notice] = "Environment \"#{@environment.name}\" created and reachable."
      rescue => e
        flash[:notice] = "Environment \"#{@environment.name}\" created, but could not reach Docker: #{e.message}"
      end
      redirect_to environments_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    if Environment.count == 1
      flash[:alert] = "Cannot delete the only environment."
      redirect_to environments_path
      return
    end

    name = @environment.name
    @environment.destroy
    flash[:notice] = "Environment \"#{name}\" deleted."
    redirect_to environments_path
  end

  def activate
    @environment.activate!
    cookies[:active_env] = { value: @environment.id.to_s, expires: 1.year.from_now }
    flash[:notice] = "Active environment set to \"#{@environment.name}\"."
    redirect_to environments_path
  end

  private

  def set_environment
    @environment = Environment.find(params[:id])
  end

  def environment_params
    params.require(:environment).permit(:name, :endpoint_type, :endpoint)
  end
end
