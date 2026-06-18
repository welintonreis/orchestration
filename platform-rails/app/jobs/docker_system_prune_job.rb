class DockerSystemPruneJob < ApplicationJob
  queue_as :default

  def perform(user_id:)
    output = `docker system prune -f 2>&1`
    user   = User.find_by(id: user_id)
    AuditLog.record(user: user, action: "docker_system_prune",
                    metadata: { output: output.strip.last(500), exit_code: $?.exitstatus })
  end
end
