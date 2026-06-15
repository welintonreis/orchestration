class Webhooks::DeploysController < ActionController::Base  # not ApplicationController — no auth
  def create
    stack = GitStack.find_by(webhook_token: params[:token])
    if stack
      GitDeployJob.perform_later(stack.id)
      render json: { status: "queued" }, status: :accepted
    else
      render json: { error: "not found" }, status: :not_found
    end
  end
end
