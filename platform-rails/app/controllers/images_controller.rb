class ImagesController < ApplicationController
  def index
    @images = current_docker_client.images
  rescue => e
    @images = []
    flash.now[:alert] = "Docker error: #{e.message}"
  end

  def show
    @image = current_docker_client.image(params[:id])
  rescue DockerClient::NotFoundError
    redirect_to images_path, alert: "Image not found."
  end

  def remove
    current_docker_client.image_remove(params[:id], force: params[:force].present?)
    redirect_to images_path, notice: "Image removed."
  rescue => e
    redirect_to images_path, alert: "Error: #{e.message}"
  end
end
