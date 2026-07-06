module Ambiente
  class GroupsController < ApplicationController
    before_action :set_group, only: %i[edit update destroy add_environment remove_environment]

    def index
      @groups = EnvironmentGroup.includes(:environments).order(:name)
      @environments = Environment.order(:name)
    end

    def new
      @group = EnvironmentGroup.new
    end

    def create
      @group = EnvironmentGroup.new(group_params)
      if @group.save
        redirect_to ambiente_groups_path, notice: "Grupo \"#{@group.name}\" criado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @group.update(group_params)
        redirect_to ambiente_groups_path, notice: "Grupo atualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @group.destroy
      redirect_to ambiente_groups_path, notice: "Grupo removido."
    end

    def add_environment
      env = Environment.find(params[:environment_id])
      @group.environments << env unless @group.environments.include?(env)
      redirect_to ambiente_groups_path, notice: "#{env.name} adicionado ao grupo."
    end

    def remove_environment
      env = Environment.find(params[:environment_id])
      @group.environments.delete(env)
      redirect_to ambiente_groups_path, notice: "#{env.name} removido do grupo."
    end

    private

    def set_group = @group = EnvironmentGroup.find(params[:id])
    def group_params = params.require(:environment_group).permit(:name, :description)
  end
end
