require "test_helper"

class Kube::ConfigMapsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Excon.defaults[:mock] = true
    sign_in users(:admin_user)
    Environment.create!(name: "k3s-cm", endpoint_type: "kubernetes",
                        kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok").activate!
  end

  teardown do
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  # No stubs registered: Excon's global mock rejects any unstubbed request, so
  # the shell rendering at all proves it never called the API.
  test "index renders the shell without calling the API" do
    get kube_config_maps_url
    assert_response :success
    assert_select "turbo-frame#configmaps-content[src]"
    assert_select "[aria-busy='true']"
  end

  test "rows renders the content" do
    Excon.stub({ path: "/api/v1/namespaces" }, { status: 200, body: { "items" => [ { "metadata" => { "name" => "default" } } ] }.to_json })
    Excon.stub({ path: "/api/v1/namespaces/default/configmaps" }, { status: 200, body: { "items" => [ { "metadata" => { "name" => "meu-configmap" }, "data" => { "chave" => "valor" } } ] }.to_json })
    get kube_rows_config_maps_url
    assert_response :success
    assert_select "turbo-frame#configmaps-content"
    assert_select "turbo-frame#configmaps-content[src]", false
    assert_select "body", text: /meu-configmap/
  end

  test "rows survives an unreachable API" do
    Excon.stub({}, { status: 500, body: "boom" })
    get kube_rows_config_maps_url
    assert_response :success
    assert_match "Kubernetes error", flash[:alert].to_s
  end
end
