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
      container:        [ { "Name" => "/web" }, "abc123" ],
      exec_run_output:  [ ls_output, "abc123", [ "ls", "-la", "/" ] ]
    )

    with_docker_client(mock) do
      get container_files_url("abc123")
      assert_response :success
    end
  end

  test "GET files with custom path passes path to ls" do
    mock = docker_client_with(
      container:       [ { "Name" => "/web" }, "abc123" ],
      exec_run_output: [ "total 0\n", "abc123", [ "ls", "-la", "/app" ] ]
    )

    with_docker_client(mock) do
      get container_files_url("abc123"), params: { path: "/app" }
      assert_response :success
    end
  end

  test "GET files sanitizes path traversal attempt to root" do
    mock = docker_client_with(
      container:       [ { "Name" => "/web" }, "abc123" ],
      exec_run_output: [ "total 0\n", "abc123", [ "ls", "-la", "/" ] ]
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
      container_archive_get: [ tar_data, "abc123", "/etc/hosts" ]
    )

    with_docker_client(mock) do
      get container_files_download_url("abc123"), params: { path: "/etc/hosts" }
      assert_response :success
      assert_equal "application/x-tar", response.content_type
    end
  end

  # files_upload action

  test "readonly user cannot upload a file" do
    sign_in(users(:readonly_user))
    file = Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "hi.txt")
    post container_files_upload_url("abc123"), params: { path: "/tmp", file: file }
    assert_redirected_to root_url
  end

  test "operator can upload a file, and it is audited" do
    sign_in(users(:operator_user))
    mock = docker_client_with(container_archive_put: [ nil, "abc123", "/tmp" ])
    file = Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "hi.txt")

    with_docker_client(mock) do
      assert_difference -> { AuditLog.count }, 1 do
        post container_files_upload_url("abc123"), params: { path: "/tmp", file: file }
      end
    end
    assert_redirected_to container_files_url("abc123", path: "/tmp")
    assert_equal "upload_container_file", AuditLog.last.action
  end

  test "upload with no file selected redirects with an alert" do
    sign_in(users(:operator_user))
    post container_files_upload_url("abc123"), params: { path: "/tmp" }
    assert_redirected_to container_files_url("abc123", path: "/tmp")
    assert_equal "Nenhum arquivo selecionado.", flash[:alert]
  end

  # files_delete action

  test "readonly user cannot delete a file" do
    sign_in(users(:readonly_user))
    delete container_files_delete_url("abc123"), params: { path: "/tmp/x" }
    assert_redirected_to root_url
  end

  test "operator can delete a file, and it is audited" do
    sign_in(users(:operator_user))
    mock = docker_client_with(exec_run_output: [ "", "abc123", [ "rm", "-rf", "--", "/tmp/x" ] ])

    with_docker_client(mock) do
      assert_difference -> { AuditLog.count }, 1 do
        delete container_files_delete_url("abc123"), params: { path: "/tmp/x" }
      end
    end
    assert_equal "delete_container_file", AuditLog.last.action
  end

  test "cannot delete the root path" do
    sign_in(users(:operator_user))
    assert_no_difference -> { AuditLog.count } do
      delete container_files_delete_url("abc123"), params: { path: "/" }
    end
    assert_equal "Caminho inválido.", flash[:alert]
  end

  # files_mkdir action

  test "readonly user cannot mkdir" do
    sign_in(users(:readonly_user))
    post container_files_mkdir_url("abc123"), params: { path: "/tmp", dir_name: "newdir" }
    assert_redirected_to root_url
  end

  test "operator can mkdir, and it is audited" do
    sign_in(users(:operator_user))
    mock = docker_client_with(exec_run_output: [ "", "abc123", [ "mkdir", "-p", "--", "/tmp/newdir" ] ])

    with_docker_client(mock) do
      assert_difference -> { AuditLog.count }, 1 do
        post container_files_mkdir_url("abc123"), params: { path: "/tmp", dir_name: "newdir" }
      end
    end
    assert_equal "mkdir_container_file", AuditLog.last.action
  end

  test "mkdir with a blank name is rejected" do
    sign_in(users(:operator_user))
    post container_files_mkdir_url("abc123"), params: { path: "/tmp", dir_name: "  " }
    assert_equal "Nome inválido.", flash[:alert]
  end

  # files_rename action

  test "readonly user cannot rename" do
    sign_in(users(:readonly_user))
    patch container_files_rename_url("abc123"), params: { path: "/tmp/old", new_name: "new" }
    assert_redirected_to root_url
  end

  test "operator can rename, and it is audited" do
    sign_in(users(:operator_user))
    mock = docker_client_with(exec_run_output: [ "", "abc123", [ "mv", "--", "/tmp/old", "/tmp/new" ] ])

    with_docker_client(mock) do
      assert_difference -> { AuditLog.count }, 1 do
        patch container_files_rename_url("abc123"), params: { path: "/tmp/old", new_name: "new" }
      end
    end
    assert_equal "rename_container_file", AuditLog.last.action
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
