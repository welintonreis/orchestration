require "test_helper"

class Kube::ServicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Excon.defaults[:mock] = true
    sign_in users(:admin_user)
    Environment.create!(name: "k3s-svc", endpoint_type: "kubernetes",
                        kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok").activate!
  end

  teardown do
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  # No stubs registered: Excon's global mock rejects any unstubbed request, so
  # the shell rendering at all proves it never called the API.
  test "index renders the shell without calling the API" do
    get kube_services_url
    assert_response :success
    assert_select "turbo-frame#services-content[src]"
    assert_select "[aria-busy='true']"
  end

  test "rows renders the content" do
    Excon.stub({ path: "/api/v1/namespaces" }, { status: 200, body: { "items" => [ { "metadata" => { "name" => "default" } } ] }.to_json })
    Excon.stub({ path: "/api/v1/namespaces/default/services" }, { status: 200, body: { "items" => [ { "metadata" => { "name" => "meu-service" }, "spec" => { "type" => "ClusterIP" } } ] }.to_json })
    get kube_rows_services_url
    assert_response :success
    assert_select "turbo-frame#services-content"
    assert_select "turbo-frame#services-content[src]", false
    assert_select "body", text: /meu-service/
  end

  test "rows survives an unreachable API" do
    Excon.stub({}, { status: 500, body: "boom" })
    get kube_rows_services_url
    assert_response :success
    assert_match "Kubernetes error", flash[:alert].to_s
  end
end
