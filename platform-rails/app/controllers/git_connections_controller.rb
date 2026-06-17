class GitConnectionsController < ApplicationController
  before_action :require_admin!
  before_action :set_git_connection, only: %i[edit update destroy status]

  def index
    @git_connections = GitConnection.order(:name)
  end

  # Lazy-loaded per row (turbo-frame, loading: :lazy) so the index page
  # renders instantly instead of blocking on N git network round-trips.
  def status
    @online = GitConnectionChecker.call(@git_connection)
    render layout: false
  end

  def new
    @git_connection = GitConnection.new(branch: "main", auth_type: "none")
  end

  def create
    @git_connection = GitConnection.new(git_connection_params)
    if @git_connection.save
      redirect_to git_connections_path, notice: "Connection \"#{@git_connection.name}\" created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @git_connection.update(git_connection_params)
      redirect_to git_connections_path, notice: "Connection \"#{@git_connection.name}\" updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @git_connection.name
    @git_connection.destroy
    redirect_to git_connections_path, notice: "Connection \"#{name}\" deleted."
  end

  private

  def set_git_connection
    @git_connection = GitConnection.find(params[:id])
  end

  def git_connection_params
    params.require(:git_connection).permit(
      :name, :repo_url, :branch, :auth_type,
      :username, :token_ciphertext, :ssh_key_ciphertext
    )
  end
end
