module Swarm
  class RegistriesController < ApplicationController
    before_action :require_admin!
    before_action :set_registry, only: %i[edit update destroy]

    def index
      @registries = SwarmRegistry.order(:name)
    end

    def new
      @registry = SwarmRegistry.new
    end

    def create
      @registry = SwarmRegistry.new(registry_params)
      if @registry.save
        redirect_to swarm_registries_path, notice: "Registry \"#{@registry.name}\" adicionado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @registry.update(registry_params)
        redirect_to swarm_registries_path, notice: "Registry atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @registry.destroy
      redirect_to swarm_registries_path, notice: "Registry removido."
    end

    private

    def set_registry
      @registry = SwarmRegistry.find(params[:id])
    end

    def registry_params
      params.require(:swarm_registry).permit(:name, :url, :username, :encrypted_password)
    end
  end
end
