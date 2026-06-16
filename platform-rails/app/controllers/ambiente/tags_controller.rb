module Ambiente
  class TagsController < ApplicationController
    before_action :require_admin!
    before_action :set_tag, only: %i[edit update destroy]

    def index
      @tags = EnvironmentTag.includes(:environments).order(:name)
    end

    def new
      @tag = EnvironmentTag.new
    end

    def create
      @tag = EnvironmentTag.new(tag_params)
      if @tag.save
        redirect_to ambiente_tags_path, notice: "Tag \"#{@tag.name}\" criada."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @tag.update(tag_params)
        redirect_to ambiente_tags_path, notice: "Tag atualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tag.destroy
      redirect_to ambiente_tags_path, notice: "Tag removida."
    end

    private

    def set_tag = @tag = EnvironmentTag.find(params[:id])
    def tag_params = params.require(:environment_tag).permit(:name, :color)
  end
end
