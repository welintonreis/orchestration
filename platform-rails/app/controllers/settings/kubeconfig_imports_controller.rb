module Settings
  class KubeconfigImportsController < ApplicationController

    def new
    end

    def create
      yaml_content = params[:kubeconfig].present? ? params[:kubeconfig].read : params[:kubeconfig_content].to_s
      @result = KubeconfigImporter.call(yaml_content)
      render :new
    rescue Psych::SyntaxError, Psych::DisallowedClass => e
      flash.now[:alert] = "Kubeconfig inválido: #{e.message}"
      render :new, status: :unprocessable_entity
    end
  end
end
