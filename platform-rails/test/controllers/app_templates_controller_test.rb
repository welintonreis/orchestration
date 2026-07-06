require "test_helper"

class AppTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  def create_template(compose_yaml: "image: {{IMAGE}}\n")
    AppTemplate.create!(name: "Test Template #{SecureRandom.hex(4)}", compose_yaml: compose_yaml)
  end

  test "index renders for any authenticated user" do
    sign_in(users(:readonly_user))
    get app_templates_url
    assert_response :success
  end

  test "readonly user cannot create a template" do
    sign_in(users(:readonly_user))
    assert_no_difference -> { AppTemplate.count } do
      post app_templates_url, params: { app_template: { name: "x", compose_yaml: "image: x\n" } }
    end
    assert_redirected_to root_url
  end

  test "admin can create, edit and destroy a template" do
    assert_difference -> { AppTemplate.count }, 1 do
      post app_templates_url, params: { app_template: { name: "My Template", compose_yaml: "image: {{IMG}}\n" } }
    end
    t = AppTemplate.find_by!(name: "My Template")
    assert_redirected_to app_templates_url

    patch app_template_url(t), params: { app_template: { description: "updated" } }
    assert_equal "updated", t.reload.description

    assert_difference -> { AppTemplate.count }, -1 do
      delete app_template_url(t)
    end
  end

  test "operator can edit a template even though it's admin-only" do
    t = create_template
    sign_in(users(:operator_user))
    patch app_template_url(t), params: { app_template: { description: "hacked" } }
    assert_redirected_to root_url
    assert_nil t.reload.description
  end

  # deploy action

  def stub_open3(stdout:, stderr:, success:)
    status = Object.new.tap { |o| o.define_singleton_method(:success?) { success } }
    original = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) { |*| [ stdout, stderr, status ] }
    yield
  ensure
    Open3.define_singleton_method(:capture3, original)
  end

  test "readonly user cannot deploy" do
    t = create_template
    sign_in(users(:readonly_user))
    post deploy_app_template_url(t), params: { stack_name: "mystack" }
    assert_redirected_to root_url
  end

  test "operator can deploy a safe template" do
    t = create_template(compose_yaml: "services:\n  web:\n    image: {{IMAGE}}\n")
    sign_in(users(:operator_user))

    assert_difference -> { AuditLog.count }, 1 do
      stub_open3(stdout: "deployed\n", stderr: "", success: true) do
        post deploy_app_template_url(t), params: { stack_name: "mystack", values: { IMAGE: "nginx:latest" } }
      end
    end
    assert_redirected_to stacks_url
    assert_equal "deploy_app_template", AuditLog.last.action
  end

  test "deploy is rejected for an invalid stack name" do
    t = create_template
    sign_in(users(:operator_user))
    post deploy_app_template_url(t), params: { stack_name: "Not Valid!" }
    assert_redirected_to app_template_url(t)
    assert_match(/inválido/, flash[:alert])
  end

  test "deploy is blocked by the safety guard and does not shell out" do
    t = create_template(compose_yaml: "services:\n  evil:\n    image: alpine\n    volumes:\n      - /var/run/docker.sock:/var/run/docker.sock\n")
    sign_in(users(:operator_user))

    original = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) { |*| flunk "must not shell out when the safety guard fails" }
    begin
      post deploy_app_template_url(t), params: { stack_name: "mystack" }
    ensure
      Open3.define_singleton_method(:capture3, original)
    end
    assert_redirected_to app_template_url(t)
    assert_match(/socket/, flash[:alert])
  end

  test "failed deploy surfaces the docker output and is still audited" do
    t = create_template
    sign_in(users(:operator_user))

    assert_difference -> { AuditLog.count }, 1 do
      stub_open3(stdout: "", stderr: "boom\n", success: false) do
        post deploy_app_template_url(t), params: { stack_name: "mystack", values: { IMAGE: "x" } }
      end
    end
    assert_redirected_to app_template_url(t)
    assert_match(/boom/, flash[:alert])
    assert_equal false, AuditLog.last.metadata["success"]
  end
end
