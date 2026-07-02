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
    when "kubernetes"   then teardown_kubernetes
    end
  end

  private

  def teardown_swarm
    client = DockerClient.new(endpoint: @stack.environment.effective_endpoint)
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
    return if @stack.repo_url.blank?

    compose_path = File.join(GitUnpacker.repo_dir(@stack).to_s, @stack.compose_file)
    return unless File.exist?(compose_path)

    host = @stack.environment.effective_endpoint
    Open3.capture3("docker", "-H", host, "compose", "-f", compose_path, "down", chdir: File.dirname(compose_path))
  end

  def teardown_kubernetes
    return if @stack.repo_url.blank?

    manifest_path = File.join(GitUnpacker.repo_dir(@stack).to_s, @stack.compose_file)
    return unless File.exist?(manifest_path)

    env = @stack.environment
    KubeClient.with_temp_kubeconfig(api_url: env.kube_api_url, token: env.kube_token, ca_cert: env.kube_ca_cert, client_cert: env.kube_client_cert, client_key: env.kube_client_key) do |kubeconfig|
      Open3.capture3(
        { "KUBECONFIG" => kubeconfig }, "kubectl", "delete", "-f", manifest_path,
        chdir: File.dirname(manifest_path)
      )
    end
  end
end
