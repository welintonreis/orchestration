# Deploys one GitStack independently to every environment in its
# target_group — the edge-compute spec's "fleet deploy", scoped down: it
# reuses GitDeployer/GitUnpacker completely unchanged per member (one repo
# checkout, then one GitDeployer.call per environment) rather than
# introducing a parallel deploy pipeline. GitDeployer always reads
# @stack.environment, so each member's deploy swaps that association in
# memory only.
#
# That swap is dirtier than it sounds: ActiveRecord#update! persists EVERY
# changed attribute on the record, not just the ones passed to it — so
# leaving environment_id "changed in memory" and later calling stack.update!
# for anything else (status, output, ...) would silently overwrite the
# stack's real target with whatever fleet member deployed last. #restore!
# sets the association back before every save this job makes, including the
# rescue path.
#
# There's no per-node history table (yet): results are aggregated into the
# stack's own status/last_deploy_output, same columns a single-environment
# deploy already uses. Good enough to see "which nodes failed" today;
# promoting to a real per-node table is a natural follow-up once fleet
# deploys are used enough to want history.
class EdgeFleetDeployJob < ApplicationJob
  queue_as :default

  def perform(git_stack_id)
    stack = GitStack.find(git_stack_id)
    original_environment = stack.environment
    group = stack.target_group
    return unless group

    members = group.environments.order(:name).to_a
    return if members.empty?

    stack.update!(status: "deploying")
    repo_path = GitUnpacker.call(stack)

    results = members.map do |env|
      stack.environment = env
      GitDeployer.call(stack, repo_path: repo_path)
      { environment: env.name, success: stack.status == "deployed", output: stack.last_deploy_output.to_s }
    end

    stack.environment = original_environment
    stack.update!(
      status:             results.all? { |r| r[:success] } ? "deployed" : "failed",
      last_deploy_output: results.map { |r| "== #{r[:environment]} ==\n#{r[:output]}" }.join("\n\n"),
      last_deployed_at:   Time.current
    )
  rescue => e
    stack&.environment = original_environment if stack && original_environment
    stack&.update!(status: "failed", last_deploy_output: "Fleet deploy error: #{e.message}")
  end
end
