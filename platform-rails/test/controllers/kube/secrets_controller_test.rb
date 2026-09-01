require "test_helper"

class Kube::SecretsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Excon.defaults[:mock] = true
    sign_in users(:admin_user)
    Environment.create!(name: "k3s-sec", endpoint_type: "kubernetes",
                        kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok").activate!
  end

  teardown do
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  # No stubs registered: Excon's global mock rejects any unstubbed request, so
  # the shell rendering at all proves it never called the API.
  test "index renders the shell without calling the API" do
    get kube_secrets_url
    assert_response :success
    assert_select "turbo-frame#secrets-content[src]"
    assert_select "[aria-busy='true']"
  end

  test "rows renders the content" do
    Excon.stub({ path: "/api/v1/namespaces" }, { status: 200, body: { "items" => [ { "metadata" => { "name" => "default" } } ] }.to_json })
    Excon.stub({ path: "/api/v1/namespaces/default/secrets" }, { status: 200, body: { "items" => [ { "metadata" => { "name" => "meu-secret" }, "type" => "Opaque" } ] }.to_json })
    get kube_rows_secrets_url
    assert_response :success
    assert_select "turbo-frame#secrets-content"
    assert_select "turbo-frame#secrets-content[src]", false
    assert_select "body", text: /meu-secret/
  end

  test "rows survives an unreachable API" do
    Excon.stub({}, { status: 500, body: "boom" })
    get kube_rows_secrets_url
    assert_response :success
    assert_match "Kubernetes error", flash[:alert].to_s
  end
end
