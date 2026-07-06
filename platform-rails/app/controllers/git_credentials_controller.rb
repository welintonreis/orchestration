class GitCredentialsController < ApplicationController
  before_action :set_git_credential, only: %i[edit update destroy]

  def index
    @git_credentials = GitCredential.order(:name)
  end

  def new
    @git_credential = GitCredential.new(auth_type: "token")
  end

  def create
    @git_credential = GitCredential.new(git_credential_params)
    if @git_credential.save
      redirect_to git_credentials_path, notice: "Credencial \"#{@git_credential.name}\" criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = git_credential_params
    attrs = attrs.reject { |k, _| k == "token_ciphertext" && attrs["token_ciphertext"].blank? }
    attrs = attrs.reject { |k, _| k == "ssh_key_ciphertext" && attrs["ssh_key_ciphertext"].blank? }
    if @git_credential.update(attrs)
      redirect_to git_credentials_path, notice: "Credencial atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @git_credential.name
    @git_credential.destroy
    redirect_to git_credentials_path, notice: "Credencial \"#{name}\" removida."
  end

  private

  def set_git_credential
    @git_credential = GitCredential.find(params[:id])
  end

  def git_credential_params
    params.require(:git_credential).permit(
      :name, :site, :auth_type, :username, :token_ciphertext, :ssh_key_ciphertext
    )
  end
end
