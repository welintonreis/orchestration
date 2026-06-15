class GitDeployJob < ApplicationJob
  queue_as :default

  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    stack.update!(status: "deploying")
    repo_path = GitUnpacker.call(stack.git_connection)
    GitDeployer.call(stack, repo_path: repo_path)
  rescue => e
    GitStack.find_by(id: git_stack_id)&.update!(
      status: "failed",
      last_deploy_output: e.message
    )
  end
end
