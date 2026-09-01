require "test_helper"

class Swarm::ServicesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  SERVICE = {
    "ID" => "svc1",
    "Version" => { "Index" => 12 },
    "CreatedAt" => "2026-01-01T00:00:00Z",
    "UpdatedAt" => "2026-01-02T00:00:00Z",
    "ServiceStatus" => { "RunningTasks" => 1, "DesiredTasks" => 1 },
    "Spec" => {
      "Name" => "meu-servico",
      "Mode" => { "Replicated" => { "Replicas" => 1 } },
      "TaskTemplate" => { "ContainerSpec" => { "Image" => "nginx:1.27" } }
    }
  }.freeze

  test "show renders the shell without touching the socket" do
    with_docker_client(fake_docker(service: :dead, service_tasks: :dead, nodes: :dead)) do
      get swarm_service_url("svc1")
      assert_response :success
      assert_select "turbo-frame#service-content[src=?]", body_swarm_service_path("svc1")
      assert_select "[aria-busy='true']"
    end
  end

  test "body renders the service detail" do
    with_docker_client(fake_docker(service: SERVICE, service_tasks: [], nodes: [])) do
      get body_swarm_service_url("svc1")
      assert_response :success
      assert_select "turbo-frame#service-content[src]", false
      assert_select "body", text: /meu-servico/
    end
  end

  # A redirect would be answered into the frame, whose id does not exist on the
  # services index — the failure has to render in place instead.
  test "body renders an in-frame error when the service is gone" do
    with_docker_client(fake_docker(service: :dead, service_tasks: :dead, nodes: :dead)) do
      get body_swarm_service_url("svc1")
      assert_response :success
      assert_select "turbo-frame#service-content", text: /Serviço não encontrado/
    end
  end
end
