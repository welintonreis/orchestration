class GitStacksController < ApplicationController
  before_action :set_git_stack, only: %i[show edit update destroy deploy]

  def index
    @git_stacks = GitStack.includes(:environment, :git_connection).order(:name)
  end

  def show
  end

  def new
    @git_stack = GitStack.new(source_type: "git", compose_file: "docker-compose.yml", deploy_mode: "swarm_stack", auto_update: false, poll_interval: 300)
    @environments    = Environment.order(:name)
    @git_connections = GitConnection.order(:name)
  end

  def create
    @git_stack = GitStack.new(git_stack_params)
    if @git_stack.save
      redirect_to @git_stack, notice: "Git stack \"#{@git_stack.name}\" created."
    else
      @environments    = Environment.order(:name)
      @git_connections = GitConnection.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @environments    = Environment.order(:name)
    @git_connections = GitConnection.order(:name)
  end

  def update
    if @git_stack.update(git_stack_params)
      redirect_to @git_stack, notice: "Git stack \"#{@git_stack.name}\" updated."
    else
      @environments    = Environment.order(:name)
      @git_connections = GitConnection.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @git_stack.name
    @git_stack.destroy
    redirect_to git_stacks_path, notice: "Git stack \"#{name}\" deleted."
  end

  def deploy
    @git_stack.update!(status: "deploying")
    GitDeployJob.perform_later(@git_stack.id)
    redirect_to @git_stack, notice: "Deploy queued for \"#{@git_stack.name}\"."
  end

  private

  def set_git_stack
    @git_stack = GitStack.find_by!(uuid: params[:id])
  end

  def git_stack_params
    params.require(:git_stack).permit(
      :name, :source_type, :compose_file, :deploy_mode,
      :auto_update, :poll_interval, :yaml_content,
      :environment_id, :git_connection_id
    )
  end
end
