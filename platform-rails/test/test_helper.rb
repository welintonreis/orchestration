ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Transactional fixtures so each test starts clean.
    fixtures :all

    # Temporarily replace a class/module method for the duration of the block.
    # Minitest 6 removed Object#stub, so we implement the same pattern manually.
    def with_stub(obj, method_name, return_value = nil, &block)
      original = obj.method(method_name)
      callable  = return_value.respond_to?(:call) ? return_value : ->(*) { return_value }
      obj.define_singleton_method(method_name) { |*args| callable.call(*args) }
      block.call
    ensure
      obj.define_singleton_method(method_name, original)
    end

    # Helper to build a valid git_stack without hitting DB callbacks in
    # places that need an unsaved record.
    def build_git_stack(overrides = {})
      env = environments(:local_env)
      GitStack.new({
        name:         "test-stack",
        source_type:  "git",
        repo_url:     "https://gitlab.example.com/repo.git",
        branch:       "main",
        compose_file: "docker-compose.yml",
        deploy_mode:  "swarm_stack",
        environment:  env,
        uuid:         SecureRandom.uuid,
        webhook_token: SecureRandom.hex(32)
      }.merge(overrides))
    end
  end
end

module ActionDispatch
  class IntegrationTest
    # Sign in via the sessions endpoint (real auth flow).
    def sign_in(user, password: "password")
      post session_url, params: { email_address: user.email_address, password: password }
    end

    # Swap the Docker client every controller (and the layout) sees. Minitest 6
    # dropped Object#stub and the project has no mocking gem, so it is
    # define_method + restore of the original UnboundMethod.
    def with_docker_client(client)
      original = ApplicationController.instance_method(:current_docker_client)
      ApplicationController.define_method(:current_docker_client) { client }
      yield
    ensure
      ApplicationController.define_method(:current_docker_client, original)
    end

    # Stub value :dead makes that call raise, which is how the skeleton shells
    # are proven not to touch the socket. Anything not listed raises
    # NoMethodError, so an unexpected call fails loudly too.
    def fake_docker(swarm: true, **stubs)
      client = Object.new
      client.define_singleton_method(:capabilities) { { swarm: swarm, compose: true, pods: false } }
      stubs.each do |name, value|
        client.define_singleton_method(name) do |*|
          raise DockerClient::ConnectionError, "stubbed dead" if value == :dead
          value
        end
      end
      client
    end
  end
end
