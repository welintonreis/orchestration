class Webhooks::DeploysController < ActionController::Base  # not ApplicationController — no auth
  # Machine-to-machine endpoint (GitHusky deploy hook, curl from CI): callers
  # have no session, so the token in the URL is the whole auth story. Without
  # this, default_protect_from_forgery (Rails 5.2+, applied to every
  # ActionController::Base subclass) 422s every POST before #create runs.
  skip_forgery_protection

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
