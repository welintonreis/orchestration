require "test_helper"

class KubeClientTest < ActiveSupport::TestCase
  def setup
    Excon.defaults[:mock] = true
  end

  def teardown
    Excon.stubs.clear
    Excon.defaults[:mock] = false
  end

  def client(ca_cert: nil)
    KubeClient.new(api_url: "https://127.0.0.1:6443", token: "test-token", ca_cert: ca_cert)
  end

  def stub_path(path, status: 200, body: {}.to_json)
    Excon.stub({ path: path }, { status: status, body: body })
  end

  test "pods returns items array" do
    stub_path("/api/v1/namespaces/default/pods", body: { "items" => [{ "metadata" => { "name" => "web-1" } }] }.to_json)
    pods = client.pods(ns: "default")
    assert_equal 1, pods.size
    assert_equal "web-1", pods.first.dig("metadata", "name")
  end

  test "deployments returns items array" do
    stub_path("/apis/apps/v1/namespaces/default/deployments", body: { "items" => [{ "metadata" => { "name" => "api" } }] }.to_json)
    assert_equal 1, client.deployments(ns: "default").size
  end

  test "nodes returns items array" do
    stub_path("/api/v1/nodes", body: { "items" => [{ "metadata" => { "name" => "k3s-node-1" } }] }.to_json)
    assert_equal 1, client.nodes.size
  end

  test "top_pods returns empty array when metrics-server is not installed (404)" do
    stub_path("/apis/metrics.k8s.io/v1beta1/namespaces/default/pods", status: 404, body: "not found")
    assert_equal [], client.top_pods(ns: "default")
  end

  test "raises NotFoundError on 404 for a normal read" do
    stub_path("/api/v1/namespaces/default/pods", status: 404, body: "not found")
    assert_raises(KubeClient::NotFoundError) { client.pods(ns: "default") }
  end

  test "raises UnauthorizedError on 401" do
    stub_path("/api/v1/nodes", status: 401, body: "unauthorized")
    assert_raises(KubeClient::UnauthorizedError) { client.nodes }
  end

  test "raises UnauthorizedError on 403" do
    stub_path("/api/v1/nodes", status: 403, body: "forbidden")
    assert_raises(KubeClient::UnauthorizedError) { client.nodes }
  end

  test "raises generic Error on 500" do
    stub_path("/api/v1/nodes", status: 500, body: "boom")
    assert_raises(KubeClient::Error) { client.nodes }
  end

  test "scale sends a merge-patch with the requested replica count" do
    Excon.stub({ path: "/apis/apps/v1/namespaces/default/deployments/api/scale" }) do |params|
      body = JSON.parse(params[:body])
      assert_equal 3, body.dig("spec", "replicas")
      { status: 200, body: "{}" }
    end
    client.scale("deployment", "api", ns: "default", replicas: 3)
  end

  test "scale raises for an unknown workload kind" do
    assert_raises(ArgumentError) { client.scale("cronjob", "x", ns: "default", replicas: 1) }
  end

  test "delete_pod issues a DELETE against the pod path" do
    Excon.stub({ method: :delete, path: "/api/v1/namespaces/default/pods/web-1" }, { status: 200, body: "{}" })
    result = client.delete_pod(ns: "default", name: "web-1")
    assert_equal({}, result)
  end

  test "apply shells out to kubectl and reports failure output" do
    result = client.apply("not: valid: yaml: [")
    assert_not result[:success]
    assert result[:output].present?
  end

  test "with_temp_kubeconfig writes a 0600 file and cleans it up" do
    path_seen = nil
    KubeClient.with_temp_kubeconfig(api_url: "https://127.0.0.1:6443", token: "tok") do |path|
      path_seen = path
      assert File.exist?(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
      content = File.read(path)
      assert_includes content, "https://127.0.0.1:6443"
      assert_includes content, "tok"
    end
    assert_not File.exist?(path_seen)
  end

  test "with_temp_kubeconfig embeds base64 client cert/key when given (mTLS)" do
    KubeClient.with_temp_kubeconfig(api_url: "https://127.0.0.1:6443", client_cert: "CERTDATA", client_key: "KEYDATA") do |path|
      content = File.read(path)
      assert_includes content, "client-certificate-data"
      assert_includes content, "client-key-data"
      assert_includes content, Base64.strict_encode64("CERTDATA")
    end
  end

  test "client without a token omits the Authorization header" do
    stub_path("/api/v1/nodes", body: { "items" => [] }.to_json)
    mtls_client = KubeClient.new(api_url: "https://127.0.0.1:6443", client_cert: "CERTDATA", client_key: "KEYDATA")
    assert_nil mtls_client.send(:headers)["Authorization"]
    assert_equal [], mtls_client.nodes
  end
end
