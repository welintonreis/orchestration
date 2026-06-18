module Ambiente
  class RegistriesController < ApplicationController
    before_action :require_admin!
    before_action :set_registry, only: %i[edit update destroy]

    def index
      @registries = EnvironmentRegistry.includes(:environment).order("environments.name")
      @environments = Environment.order(:name)
    end

    def new
      @registry = EnvironmentRegistry.new
      @environments = Environment.order(:name)
    end

    def create
      @registry = EnvironmentRegistry.new(registry_params)
      if @registry.save
        redirect_to ambiente_registries_path, notice: "Registry adicionado."
      else
        @environments = Environment.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @environments = Environment.order(:name)
    end

    def update
      if @registry.update(registry_params)
        redirect_to ambiente_registries_path, notice: "Registry atualizado."
      else
        @environments = Environment.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @registry.destroy
      redirect_to ambiente_registries_path, notice: "Registry removido."
    end

    private

    def set_registry = @registry = EnvironmentRegistry.find(params[:id])
    def registry_params
      params.require(:environment_registry).permit(:environment_id, :url, :username, :encrypted_password)
    end
  end
end
