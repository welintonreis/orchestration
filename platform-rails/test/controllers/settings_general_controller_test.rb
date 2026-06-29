require "test_helper"

class Settings::GeneralControllerTest < ActionDispatch::IntegrationTest
  setup do
    # docker.info will raise (no daemon in test env) — rescued to {} in the action
    sign_in users(:admin_user)
  end

  test "GET index requires authentication" do
    delete session_url
    get settings_general_url
    assert_response :redirect
  end

  test "GET index requires admin role" do
    sign_in users(:readonly_user)
    get settings_general_url
    assert_response :redirect
  end

  test "GET index renders for admin" do
    get settings_general_url
    assert_response :success
  end

  test "GET index exposes app_name from AppSetting" do
    AppSetting.set("app_name", "TestOrch")
    get settings_general_url
    assert_response :success
    assert_select "input[value='TestOrch']"
  end

  test "POST update saves settings and redirects" do
    post settings_general_url, params: { app_name: "NewName", alert_webhook_url: "https://hook.example.com/path" }
    assert_redirected_to settings_general_url
    assert_equal "NewName", AppSetting.get("app_name")
    assert_equal "https://hook.example.com/path", AppSetting.get("alert_webhook_url")
  end

  test "POST update requires admin" do
    sign_in users(:operator_user)
    post settings_general_url, params: { app_name: "Hacked" }
    assert_response :redirect
    assert_not_equal "Hacked", AppSetting.get("app_name")
  end
end
