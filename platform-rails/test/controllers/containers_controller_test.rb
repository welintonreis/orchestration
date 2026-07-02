require "test_helper"

class ContainersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  # files action

  test "GET files requires authentication" do
    delete session_url
    get container_files_url("abc123")
    assert_response :redirect
  end

  test "GET files redirects to containers when container not found" do
    with_docker_client(docker_client_raising(DockerClient::NotFoundError)) do
      get container_files_url("nonexistent")
      assert_redirected_to containers_url
    end
  end

  test "GET files renders listing on success" do
    ls_output = "total 8\ndrwxr-xr-x 2 root root 4096 Jan 1 00:00 etc\n-rw-r--r-- 1 root root 100 Jan 1 00:00 hosts"
    mock = docker_client_with(
      container:        [{ "Name" => "/web" }, "abc123"],
      exec_run_output:  [ls_output, "abc123", ["ls", "-la", "/"]]
    )

    with_docker_client(mock) do
      get container_files_url("abc123")
      assert_response :success
    end
  end

  test "GET files with custom path passes path to ls" do
    mock = docker_client_with(
      container:       [{ "Name" => "/web" }, "abc123"],
      exec_run_output: ["total 0\n", "abc123", ["ls", "-la", "/app"]]
    )

    with_docker_client(mock) do
      get container_files_url("abc123"), params: { path: "/app" }
      assert_response :success
    end
  end

  test "GET files sanitizes path traversal attempt to root" do
    mock = docker_client_with(
      container:       [{ "Name" => "/web" }, "abc123"],
      exec_run_output: ["total 0\n", "abc123", ["ls", "-la", "/"]]
    )

    with_docker_client(mock) do
      get container_files_url("abc123"), params: { path: "/../etc/passwd" }
      assert_response :success
    end
  end

  # files_download action

  test "GET files_download requires authentication" do
    delete session_url
    get container_files_download_url("abc123"), params: { path: "/etc/hosts" }
    assert_response :redirect
  end

  test "GET files_download sends file as tar" do
    tar_data = "fake tar bytes"
    mock = docker_client_with(
      container_archive_get: [tar_data, "abc123", "/etc/hosts"]
    )

    with_docker_client(mock) do
      get container_files_download_url("abc123"), params: { path: "/etc/hosts" }
      assert_response :success
      assert_equal "application/x-tar", response.content_type
    end
  end

  private

  # Temporarily override current_docker_client on ApplicationController.
  def with_docker_client(mock_client, &block)
    orig = ApplicationController.instance_method(:current_docker_client)
    ApplicationController.define_method(:current_docker_client) { mock_client }
    block.call
  ensure
    ApplicationController.define_method(:current_docker_client, orig)
  end

  # Build a simple stub docker client. Each key is a method name;
  # value is [return_value, *expected_args]. Returns the return_value
  # and ignores (not verifies) the args — keeps tests simple without
  # a full mock library.
  def docker_client_with(methods)
    obj = Object.new
    obj.define_singleton_method(:capabilities) { { swarm: false, compose: true, pods: false } }
    methods.each do |method_name, (return_val, *)|
      obj.define_singleton_method(method_name) { |*| return_val }
    end
    obj
  end

  def docker_client_raising(error_class)
    obj = Object.new
    obj.define_singleton_method(:capabilities) { { swarm: false, compose: true, pods: false } }
    obj.define_singleton_method(:container) { |*| raise error_class }
    obj.define_singleton_method(:exec_run_output) { |*| raise error_class }
    obj
  end
end
