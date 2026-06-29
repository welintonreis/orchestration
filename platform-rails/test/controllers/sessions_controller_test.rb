require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "GET new renders login form" do
    get new_session_url
    assert_response :success
  end

  test "POST create with valid credentials starts session and redirects" do
    user = users(:admin_user)
    post session_url, params: { email_address: user.email_address, password: "password" }
    assert_response :redirect
    assert_not_equal new_session_url, response.location
  end

  test "POST create with wrong password redirects to login with alert" do
    user = users(:admin_user)
    post session_url, params: { email_address: user.email_address, password: "wrongpassword" }
    assert_redirected_to new_session_url
  end

  test "POST create with unknown email redirects to login" do
    post session_url, params: { email_address: "nobody@example.com", password: "password" }
    assert_redirected_to new_session_url
  end

  test "POST create with inactive user redirects to login with alert" do
    user = users(:inactive_user)
    post session_url, params: { email_address: user.email_address, password: "password" }
    assert_redirected_to new_session_url
  end

  test "DELETE destroy terminates session and redirects to login" do
    sign_in users(:admin_user)
    delete session_url
    assert_redirected_to new_session_url
  end

  test "unauthenticated request to protected route redirects to login" do
    get root_url
    assert_response :redirect
  end
end
