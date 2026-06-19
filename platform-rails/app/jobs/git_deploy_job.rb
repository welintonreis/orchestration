class GitDeployJob < ApplicationJob
  queue_as :default

  # target_sha set → rollback: check out that exact commit before deploying,
  # instead of the branch HEAD that GitUnpacker.call would pull.
  def perform(git_stack_id, target_sha = nil)
    stack = GitStack.find(git_stack_id)
    stack.update!(status: "deploying")
    repo_path = target_sha.present? ? GitUnpacker.checkout(stack, target_sha) : GitUnpacker.call(stack)
    GitDeployer.call(stack, repo_path: repo_path)
  rescue => e
    GitStack.find_by(id: git_stack_id)&.update!(
      status: "failed",
      last_deploy_output: e.message
    )
  end
end
