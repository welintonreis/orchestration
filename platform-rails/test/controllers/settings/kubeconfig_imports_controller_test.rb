require "test_helper"
require "base64"

class Settings::KubeconfigImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Excon.defaults[:mock] = true
    Excon.stub({ path: "/version" }, { status: 200, body: "{}" })
    # Full-page renders go through the layout, which independently probes
    # the *Docker* API (runtime_capabilities, for Swarm nav visibility) —
    # unrelated to this controller, but Excon's global mock rejects any
    # unstubbed request, so it needs a catch-all too. Registered after the
    # specific k8s /version stub above so that one still matches first.
    Excon.stub({}, { status: 200, body: { "Components" => [] }.to_json })
    sign_in users(:admin_user)
  end

  teardown do
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  def sample_kubeconfig
    <<~YAML
      apiVersion: v1
      kind: Config
      clusters:
        - name: cluster-a
          cluster:
            server: https://cluster-a.example.com:6443
            certificate-authority-data: #{Base64.strict_encode64("CA-A")}
      users:
        - name: user-a
          user:
            token: token-a
      contexts:
        - name: ctx-a
          context:
            cluster: cluster-a
            user: user-a
    YAML
  end

  test "GET new requires admin role" do
    sign_in users(:readonly_user)
    get settings_kubeconfig_import_url
    assert_response :redirect
  end

  test "GET new renders for admin" do
    get settings_kubeconfig_import_url
    assert_response :success
  end

  test "POST create imports contexts from pasted content" do
    assert_difference "Environment.count", 1 do
      post settings_kubeconfig_import_url, params: { kubeconfig_content: sample_kubeconfig }
    end
    assert_response :success
    assert_select "body", text: /cluster-a\/ctx-a/
  end

  test "POST create shows a clear error for garbage YAML instead of a stacktrace" do
    post settings_kubeconfig_import_url, params: { kubeconfig_content: "not: yaml: [" }
    assert_response :unprocessable_entity
    assert_match "inválido", flash[:alert].to_s
  end
end
