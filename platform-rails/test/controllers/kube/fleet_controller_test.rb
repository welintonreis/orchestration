require "test_helper"

class Kube::FleetControllerTest < ActionDispatch::IntegrationTest
  setup do
    Excon.defaults[:mock] = true
    # The layout independently probes the *Docker* API for Swarm nav
    # visibility on every full-page render — unrelated to this controller,
    # but needs a catch-all since Excon's global mock rejects unstubbed
    # requests. Registered first so more specific per-test stubs still win.
    Excon.stub({}, { status: 200, body: { "Components" => [] }.to_json })
    sign_in users(:admin_user)
  end

  teardown do
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  def stub_healthy_cluster
    Excon.stub({ path: "/version" }, { status: 200, body: { "gitVersion" => "v1.31.4" }.to_json })
    Excon.stub({ path: "/api/v1/nodes" }, { status: 200, body: { "items" => [{ "status" => { "conditions" => [{ "type" => "Ready", "status" => "True" }] } }] }.to_json })
    Excon.stub({ path: "/api/v1/pods" }, { status: 200, body: { "items" => [] }.to_json })
    Excon.stub({ path: "/apis/apps/v1/deployments" }, { status: 200, body: { "items" => [] }.to_json })
  end

  test "index shows no clusters registered when there are none" do
    get kube_fleet_url
    assert_response :success
    assert_select "body", text: /Nenhum environment Kubernetes/
  end

  test "index reports an online cluster with its node/pod/deployment summary" do
    Environment.create!(name: "k3s-fleet-test", endpoint_type: "kubernetes", kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok")
    stub_healthy_cluster

    get kube_fleet_url
    assert_response :success
    assert_select "body", text: /k3s-fleet-test/
    assert_select "body", text: /Online/
  end

  test "index marks an unreachable cluster offline without erroring the whole page" do
    Environment.create!(name: "k3s-fleet-offline", endpoint_type: "kubernetes", kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok")
    Excon.stub({ path: "/version" }, { status: 500, body: "boom" })
    Excon.stub({}, { status: 500, body: "boom" })

    get kube_fleet_url
    assert_response :success
    assert_select "body", text: /Offline/
  end
end
