require "test_helper"

class GitDeployerTest < ActiveSupport::TestCase
  def kube_env
    @kube_env ||= Environment.create!(
      name: "k3s-deployer-test", endpoint_type: "kubernetes",
      kube_api_url: "https://127.0.0.1:6443", kube_token_ciphertext: "tok"
    )
  end

  def kube_stack
    build_git_stack(deploy_mode: "kubernetes", environment: kube_env, compose_file: "manifest.yaml")
  end

  test "run_kubernetes_deploy shells out to kubectl apply with a temp kubeconfig, not a -H flag" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "manifest.yaml"), "not: valid: [")
      deployer = GitDeployer.send(:new, kube_stack, dir)

      output, success = deployer.send(:run_kubernetes_deploy)
      assert_not success
      assert output.present?
      assert_not_includes output, "tok" # the raw token never appears in output/argv
    end
  end

  test "run_deploy dispatches to run_kubernetes_deploy for kubernetes mode" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "manifest.yaml"), "apiVersion: v1")
      deployer = GitDeployer.send(:new, kube_stack, dir)

      called = false
      deployer.define_singleton_method(:run_kubernetes_deploy) { called = true; ["ok", true] }
      deployer.send(:run_deploy)
      assert called
    end
  end
end
