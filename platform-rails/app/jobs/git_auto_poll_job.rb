class GitAutoPollJob < ApplicationJob
  queue_as :default

  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    return unless stack.auto_update?

    new_sha = GitPollService.call(stack.git_connection)
    return if new_sha.nil? || new_sha == stack.git_connection.last_commit_sha

    GitDeployJob.perform_later(git_stack_id)
  end
end
