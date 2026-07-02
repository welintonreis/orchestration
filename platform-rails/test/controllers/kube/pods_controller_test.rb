require "test_helper"

class Kube::PodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Excon.defaults[:mock] = true
    sign_in users(:admin_user)
    @kube_env = Environment.create!(name: "k3s-test", endpoint_type: "kubernetes", kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok")
    @kube_env.activate!
  end

  teardown do
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  test "redirects away when active environment is not kubernetes" do
    environments(:local_env).activate!
    get kube_pods_url
    assert_redirected_to root_url
  end

  test "index lists pods for the current namespace" do
    Excon.stub({ path: "/api/v1/namespaces" }, { status: 200, body: { "items" => [{ "metadata" => { "name" => "default" } }] }.to_json })
    Excon.stub({ path: "/api/v1/namespaces/default/pods" }, { status: 200, body: { "items" => [{ "metadata" => { "name" => "web-1" } }] }.to_json })

    get kube_pods_url
    assert_response :success
    assert_select "body", text: /web-1/
  end

  test "index shows a flash and empty list when the API is unreachable" do
    Excon.stub({ path: "/api/v1/namespaces" }, { status: 500, body: "boom" })
    Excon.stub({ path: "/api/v1/namespaces/default/pods" }, { status: 500, body: "boom" })

    get kube_pods_url
    assert_response :success
    assert_match "Kubernetes error", flash[:alert].to_s
  end

  test "destroy requires operator role" do
    sign_in users(:readonly_user)
    delete kube_pod_url("web-1")
    assert_response :redirect
  end

  test "destroy removes the pod and redirects" do
    Excon.stub({ method: :delete, path: "/api/v1/namespaces/default/pods/web-1" }, { status: 200, body: "{}" })
    delete kube_pod_url("web-1")
    assert_redirected_to kube_pods_path(ns: "default")
  end
end
