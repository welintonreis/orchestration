class GitConnectionsController < ApplicationController
  before_action :require_admin!
  before_action :set_git_connection, only: %i[edit update destroy status files]

  def index
    @git_connections = GitConnection.order(:name)
  end

  # Lazy-loaded per row (turbo-frame, loading: :lazy) so the index page
  # doesn't block on N git network round-trips.
  def status
    @online = GitConnectionChecker.call(@git_connection)
    render layout: false
  end

  # Backs the compose-file autocomplete/validator on git_stacks/new —
  # ensures the repo is cloned (or pulls if already present, via the same
  # GitUnpacker the actual deploy uses) and lists every yml/yaml path so
  # the wizard can tell the user whether what they typed actually exists.
  def files
    repo_path = GitUnpacker.call(@git_connection)
    render json: Dir.glob("**/*.{yml,yaml}", base: repo_path.to_s).sort
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
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
