class GitAutoPollJob < ApplicationJob
  queue_as :default

  # Pull-based reconcile tick. Detects a new upstream commit (cheap ls-remote),
  # refreshes drift against the live swarm, then decides whether to apply:
  #   - new commit          → deploy (inside sync window)
  #   - drift + self_heal    → re-apply git state (inside sync window)
  # Outside the sync window the divergence is left visible (OutOfSync) and an
  # alert is raised instead of deploying.
  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    return unless stack.auto_update?

    prev_sha       = stack.last_commit_sha
    new_sha        = GitPollService.call(stack)
    commit_changed = new_sha.present? && new_sha != prev_sha

    # Skip the expensive git pull + drift inspect when nothing changed and
    # self_heal is off. For large swarms (dozens of stacks) this avoids an
    # O(N) fan-out of git clones + docker service inspects every poll cycle.
    unless commit_changed || stack.self_heal?
      stack.update_column(:last_commit_sha, new_sha) if new_sha.present? && new_sha != prev_sha
      return
    end

    # Pull + read-only drift check (also advances last_commit_sha to new_sha).
    repo = GitUnpacker.call(stack)
    GitDriftService.call(stack, repo_path: repo)
    stack.reload

    needs_deploy = commit_changed || (stack.self_heal? && stack.out_of_sync?)
    return unless needs_deploy

    if stack.within_sync_window?
      GitDeployJob.perform_later(stack.id)
    else
      Alert.create!(
        level:    "warning",
        resource: "git_deploy",
        message:  "Git stack \"#{stack.name}\" #{commit_changed ? 'has a new commit' : 'drifted'} but is outside its sync window — deploy deferred"
      )
    end
  end
end
