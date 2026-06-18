require "open3"

# Runs before a GitStack record is destroyed — without this, deleting the
# DB record (GitStacksController#destroy) left the actual swarm services
# (or compose containers) running forever, orphaned with no record to
# manage them from.
class GitStackTeardown
  def self.call(git_stack)
    new(git_stack).call
  end

  def initialize(git_stack)
    @stack = git_stack
  end

  def call
    case @stack.deploy_mode
    when "swarm_stack" then teardown_swarm
    when "compose"      then teardown_compose
    end
  end

  private

  def teardown_swarm
    client = DockerClient.new(endpoint: @stack.environment.endpoint)
    services_in_stack(client).each do |svc|
      id = svc["ID"]
      client.service_scale(id, 0)
      client.service_remove(id)
    end
  end

  def services_in_stack(client)
    client.services.select { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") == @stack.name }
  end

  def teardown_compose
    return if @stack.git_connection.nil?

    compose_path = File.join(GitUnpacker.repo_dir(@stack.git_connection).to_s, @stack.compose_file)
    return unless File.exist?(compose_path)

    Open3.capture3("docker", "compose", "-f", compose_path, "down", chdir: File.dirname(compose_path))
  end
end
