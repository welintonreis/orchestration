require "test_helper"

class CloudflareDnsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  # Turbo follows a form redirect with `Accept: text/vnd.turbo-stream.html`.
  # The index has no turbo_stream template, so declaring one in respond_to
  # made Rails answer 406 — Turbo dropped the page and nothing updated until F5.
  test "GET index answers HTML even when Turbo asks for a turbo-stream" do
    get cloudflare_dns_url, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    assert_response :success
    assert_match "text/html", response.media_type
  end
end
