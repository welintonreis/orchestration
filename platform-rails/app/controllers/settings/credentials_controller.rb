module Settings
  class CredentialsController < ApplicationController
    before_action :require_admin!
    before_action :set_credential, only: %i[edit update destroy]

    def index
      @credentials = SharedCredential.order(:name)
    end

    def new
      @credential = SharedCredential.new
    end

    def create
      @credential = SharedCredential.new(credential_params)
      if @credential.save
        redirect_to settings_credentials_path, notice: "Credencial \"#{@credential.name}\" criada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      attrs = credential_params
      attrs = attrs.reject { |k, _| k == "encrypted_secret" && attrs["encrypted_secret"].blank? }
      if @credential.update(attrs)
        redirect_to settings_credentials_path, notice: "Credencial atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @credential.destroy
      redirect_to settings_credentials_path, notice: "Credencial removida."
    end

    private

    def set_credential = @credential = SharedCredential.find(params[:id])
    def credential_params
      params.require(:shared_credential).permit(:name, :credential_type, :username, :encrypted_secret, :description)
    end
  end
end
