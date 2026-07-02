require "test_helper"
require "base64"

class KubeconfigImporterTest < ActiveSupport::TestCase
  def setup
    Excon.defaults[:mock] = true
  end

  def teardown
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  def sample_kubeconfig(contexts_yaml: nil)
    <<~YAML
      apiVersion: v1
      kind: Config
      clusters:
        - name: cluster-a
          cluster:
            server: https://cluster-a.example.com:6443
            certificate-authority-data: #{Base64.strict_encode64("CA-A")}
        - name: cluster-b
          cluster:
            server: https://cluster-b.example.com:6443
            certificate-authority-data: #{Base64.strict_encode64("CA-B")}
      users:
        - name: user-a
          user:
            token: token-a
        - name: user-b
          user:
            client-certificate-data: #{Base64.strict_encode64("CERT-B")}
            client-key-data: #{Base64.strict_encode64("KEY-B")}
      contexts:
        - name: ctx-a
          context:
            cluster: cluster-a
            user: user-a
        - name: ctx-b
          context:
            cluster: cluster-b
            user: user-b
      current-context: ctx-a
    YAML
  end

  test "imports one environment per context with token or mTLS creds" do
    Excon.stub({ path: "/version" }, { status: 200, body: "{}" })

    assert_difference "Environment.count", 2 do
      result = KubeconfigImporter.call(sample_kubeconfig)
      assert_equal 2, result.created.size
      assert_empty result.skipped
    end

    env_a = Environment.find_by(name: "cluster-a/ctx-a")
    assert_equal "https://cluster-a.example.com:6443", env_a.kube_api_url
    assert_equal "CA-A", env_a.kube_ca_cert
    assert_equal "token-a", env_a.kube_token

    env_b = Environment.find_by(name: "cluster-b/ctx-b")
    assert_equal "CERT-B", env_b.kube_client_cert
    assert_equal "KEY-B", env_b.kube_client_key
  end

  test "flags unreachable clusters without blocking the rest of the import" do
    Excon.stub({ path: "/version" }, { status: 500, body: "boom" })

    assert_difference "Environment.count", 2 do
      result = KubeconfigImporter.call(sample_kubeconfig)
      assert_equal 2, result.created.size
      assert result.created.all? { |c| c.reachable == false }
    end
  end

  test "skips a context whose cluster is missing" do
    yaml = <<~YAML
      apiVersion: v1
      kind: Config
      clusters: []
      users: []
      contexts:
        - name: orphan-ctx
          context:
            cluster: nonexistent
            user: nobody
    YAML

    result = KubeconfigImporter.call(yaml)
    assert_empty result.created
    assert_equal 1, result.skipped.size
    assert_match "not found", result.skipped.first.reason
  end

  test "skips a context whose environment name already exists" do
    Excon.stub({ path: "/version" }, { status: 200, body: "{}" })
    Environment.create!(name: "cluster-a/ctx-a", endpoint_type: "kubernetes", kube_api_url: "https://existing:6443")

    result = KubeconfigImporter.call(sample_kubeconfig)
    assert_equal 1, result.created.size
    assert_equal 1, result.skipped.size
    assert_match "already exists", result.skipped.first.reason
  end
end
