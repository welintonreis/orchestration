require "test_helper"

class EnvironmentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  # The whole point of splitting index/rows: index must not touch the Docker
  # socket, so a dead or slow daemon can't stall the page before the skeleton
  # paints. If someone moves the probing back into index, this fails.
  test "GET index renders the shell without probing Docker" do
    with_docker(dead_client) do
      get environments_url
      assert_response :success
      assert_select "turbo-frame#environments-content[src=?]", rows_environments_path
      assert_select "[aria-busy='true']"
      # The skeleton is a placeholder, not the real cards.
      assert_select "turbo-frame#environments-content a", false
    end
  end

  test "GET rows renders the cards" do
    with_docker(live_client) do
      get rows_environments_url
      assert_response :success
      assert_select "turbo-frame#environments-content"
      assert_select "turbo-frame#environments-content[src]", false
    end
  end

  # A down daemon degrades to an offline card, never a 500.
  test "GET rows survives an unreachable daemon" do
    with_docker(dead_client) do
      get rows_environments_url
      assert_response :success
    end
  end

  private

  # EnvironmentsController builds its own DockerClient per environment, so
  # stubbing current_docker_client alone isn't enough — .new has to go too.
  def with_docker(client)
    orig = ApplicationController.instance_method(:current_docker_client)
    ApplicationController.define_method(:current_docker_client) { client }
    DockerClient.define_singleton_method(:new) { |**| client }
    yield
  ensure
    ApplicationController.define_method(:current_docker_client, orig)
    DockerClient.singleton_class.send(:remove_method, :new)
  end

  def base_client
    obj = Object.new
    obj.define_singleton_method(:capabilities) { { swarm: false, compose: true, pods: false } }
    obj
  end

  def live_client
    obj = base_client
    obj.define_singleton_method(:info) { |*| { "ServerVersion" => "27.0", "NCPU" => 4, "MemTotal" => 1024, "Swarm" => { "LocalNodeState" => "inactive" } } }
    %i[containers images networks].each { |m| obj.define_singleton_method(m) { |*| [] } }
    obj.define_singleton_method(:volumes) { |*| { "Volumes" => [] } }
    obj
  end

  def dead_client
    obj = base_client
    %i[info containers images volumes networks services nodes].each do |m|
      obj.define_singleton_method(m) { |*| raise DockerClient::ConnectionError }
    end
    obj
  end
end
