class GitDriftJob < ApplicationJob
  queue_as :default

  # Pulls the repo (so the desired compose reflects the target branch) and runs
  # the read-only drift check. Never deploys — only updates sync_status/health.
  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    repo  = GitUnpacker.call(stack)
    GitDriftService.call(stack, repo_path: repo)
  rescue => e
    GitStack.find_by(id: git_stack_id)&.update_columns(
      sync_status: "unknown", health: "unknown",
      drift_detail: { error: e.message }.to_json, last_drift_at: Time.current
    )
  end
end
