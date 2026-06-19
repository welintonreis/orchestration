class GitStacksController < ApplicationController
  before_action :set_git_stack, only: %i[show edit update destroy deploy sync rollback refresh_drift]

  def index
    @git_stacks = GitStack.includes(:environment, :git_credential).order(:name)
  end

  def show
  end

  def new
    @git_stack = GitStack.new(source_type: "git", compose_file: "docker-compose.yml", deploy_mode: "swarm_stack", auto_update: false, poll_interval: 300, branch: "main")
    @environments    = Environment.order(:name)
    @git_credentials = GitCredential.order(:name)
  end

  def create
    @git_stack = GitStack.new(git_stack_params)
    if attach_credential! && @git_stack.save
      redirect_to @git_stack, notice: "Git stack \"#{@git_stack.name}\" created."
    else
      @environments    = Environment.order(:name)
      @git_credentials = GitCredential.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @environments    = Environment.order(:name)
    @git_credentials = GitCredential.order(:name)
  end

  def update
    @git_stack.assign_attributes(git_stack_params)
    if attach_credential! && @git_stack.save
      redirect_to @git_stack, notice: "Git stack \"#{@git_stack.name}\" updated."
    else
      @environments    = Environment.order(:name)
      @git_credentials = GitCredential.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  # Backs the compose-file autocomplete/validator on git_stacks/new — clones
  # (or pulls, via the same GitUnpacker the actual deploy uses) the repo
  # for whatever repo_url/branch/credential combo is currently filled in,
  # and lists every yml/yaml path so the wizard can tell the user whether
  # what they typed actually exists. POST (not GET) since this carries a
  # raw token/password when the user hasn't saved a credential yet —
  # those shouldn't ride along in a URL/query string.
  def files
    preview = GitStack.new(
      repo_url:          params[:repo_url],
      branch:            params[:branch].presence || "main",
      git_credential_id: params[:git_credential_id].presence,
      username:          params[:username],
      token_ciphertext:  params[:token]
    )
    repo_path = GitUnpacker.call(preview)
    render json: Dir.glob("**/*.{yml,yaml}", base: repo_path.to_s).sort
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    name = @git_stack.name
    begin
      GitStackTeardown.call(@git_stack)
    rescue => e
      redirect_to @git_stack, alert: "Falha ao remover serviços/containers: #{e.message}. Stack não foi deletada." and return
    end
    @git_stack.destroy
    redirect_to git_stacks_path, notice: "Git stack \"#{name}\" deleted."
  end

  def deploy
    @git_stack.update!(status: "deploying")
    GitDeployJob.perform_later(@git_stack.id)
    redirect_to @git_stack, notice: "Deploy queued for \"#{@git_stack.name}\"."
  end

  # Apply the desired git state to reconcile drift (Argo-style "Sync"). Same
  # mechanism as deploy — name reflects intent in the UI.
  def sync
    @git_stack.update!(status: "deploying")
    GitDeployJob.perform_later(@git_stack.id)
    redirect_to @git_stack, notice: "Sync iniciado para \"#{@git_stack.name}\"."
  end

  def rollback
    sha = params[:sha].presence
    return redirect_to @git_stack, alert: "Revisão inválida." if sha.blank?

    @git_stack.update!(status: "deploying")
    GitDeployJob.perform_later(@git_stack.id, sha)
    redirect_to @git_stack, notice: "Rollback para #{sha.first(12)} iniciado."
  end

  # Read-only drift refresh — recomputes sync_status/health against live swarm.
  def refresh_drift
    GitDriftJob.perform_later(@git_stack.id)
    redirect_to @git_stack, notice: "Verificando divergência…"
  end

  private

  def set_git_stack
    @git_stack = GitStack.find_by!(uuid: params[:id])
  end

  def git_stack_params
    params.require(:git_stack).permit(
      :name, :source_type, :compose_file, :deploy_mode,
      :auto_update, :poll_interval, :yaml_content, :env_content,
      :environment_id, :repo_url, :branch, :git_credential_id,
      :username, :token_ciphertext,
      :self_heal, :sync_window, :pre_sync_cmd, :post_sync_cmd
    )
  end

  # "Salvar credenciais para deploy futuro" checkbox on the inline
  # username/token fields — turns them into a real GitCredential and
  # points the stack at it instead of carrying the token on itself.
  # Returns false (and adds an error) if the checkbox was on but the
  # credential couldn't be created, so the caller knows to re-render.
  def attach_credential!
    return true unless params.dig(:git_stack, :save_credential) == "1"
    return true if @git_stack.username.blank? || @git_stack.token_ciphertext.blank?

    name = params.dig(:git_stack, :new_credential_name).presence || @git_stack.name
    site = URI.parse(@git_stack.repo_url.to_s).host.presence || @git_stack.repo_url
    credential = GitCredential.create!(
      name: name, site: site, auth_type: "token",
      username: @git_stack.username, token_ciphertext: @git_stack.token_ciphertext
    )
    @git_stack.git_credential = credential
    @git_stack.username = nil
    @git_stack.token_ciphertext = nil
    true
  rescue URI::Error, ActiveRecord::RecordInvalid => e
    @git_stack.errors.add(:base, "Não foi possível salvar a credencial: #{e.message}")
    false
  end
end
