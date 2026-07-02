require "test_helper"

class GitStackTeardownTest < ActiveSupport::TestCase
  def kube_env
    @kube_env ||= Environment.create!(
      name: "k3s-teardown-test", endpoint_type: "kubernetes",
      kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok"
    )
  end

  test "teardown_kubernetes is a no-op when there is no repo_url" do
    stack = build_git_stack(deploy_mode: "kubernetes", environment: kube_env, source_type: "yaml", repo_url: nil, yaml_content: "x")
    assert_nothing_raised { GitStackTeardown.call(stack) }
  end

  test "teardown_kubernetes shells kubectl delete when the manifest exists" do
    stack = build_git_stack(deploy_mode: "kubernetes", environment: kube_env, compose_file: "manifest.yaml")

    Dir.mktmpdir do |dir|
      with_stub(GitUnpacker, :repo_dir, dir) do
        File.write(File.join(dir, "manifest.yaml"), "apiVersion: v1")
        assert_nothing_raised { GitStackTeardown.call(stack) }
      end
    end
  end
end
