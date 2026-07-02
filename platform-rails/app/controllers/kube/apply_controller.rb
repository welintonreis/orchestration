module Kube
  class ApplyController < ApplicationController
    include RequireKubernetes
    before_action :require_operator!, only: %i[create]

    def new
    end

    def create
      result = current_kube_client.apply(params[:yaml_content].to_s)
      @output = result[:output]
      if result[:success]
        flash.now[:notice] = "Manifest applied."
      else
        flash.now[:alert] = "Apply failed — nothing was applied that didn't already succeed server-side."
      end
      render :new
    end
  end
end
