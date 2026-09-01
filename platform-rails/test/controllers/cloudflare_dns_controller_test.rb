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

  # index must answer without a single Cloudflare roundtrip — the zone list and
  # the records are both external HTTPS calls, and they used to run before the
  # first byte.
  test "GET index renders the shell without calling the Cloudflare API" do
    with_service(dead_service) do
      get cloudflare_dns_url
      assert_response :success
      assert_select "turbo-frame#cloudflare-dns-content[src]"
      assert_select "[aria-busy='true']"
    end
  end

  test "GET rows renders the records table" do
    with_service(live_service) do
      get rows_cloudflare_dns_url
      assert_response :success
      assert_select "turbo-frame#cloudflare-dns-content"
      assert_select "turbo-frame#cloudflare-dns-content[src]", false
      assert_match "dns.example.com", response.body
    end
  end

  # A frame navigation from a tab/filter link inside rows lands on index; it
  # must render the rows, not a second nested frame that never fetches.
  test "GET index as a turbo-frame request renders the rows" do
    with_service(live_service) do
      get cloudflare_dns_url, headers: { "Turbo-Frame" => "cloudflare-dns-content" }
      assert_response :success
      assert_select "turbo-frame#cloudflare-dns-content[src]", false
      assert_match "dns.example.com", response.body
    end
  end

  test "GET rows degrades to an error banner when the API is down" do
    with_service(dead_service) do
      get rows_cloudflare_dns_url
      assert_response :success
      assert_match "cloudflare fora do ar", response.body
    end
  end

  private

  # The controller builds its own CloudflareService, so .new is what has to go.
  def with_service(service)
    CloudflareService.define_singleton_method(:new) { |**| service }
    yield
  ensure
    CloudflareService.singleton_class.send(:remove_method, :new)
  end

  def live_service
    obj = Object.new
    obj.define_singleton_method(:configured?) { true }
    obj.define_singleton_method(:default_zone_id) { "zone-1" }
    obj.define_singleton_method(:list_zones) { [ { "id" => "zone-1", "name" => "example.com" } ] }
    obj.define_singleton_method(:list_dns_records) do |**|
      { records: [ { "id" => "r1", "type" => "A", "name" => "dns.example.com", "content" => "1.2.3.4",
                     "ttl" => 1, "proxied" => false } ], info: {} }
    end
    obj
  end

  def dead_service
    obj = Object.new
    obj.define_singleton_method(:configured?) { true }
    obj.define_singleton_method(:default_zone_id) { "zone-1" }
    obj.define_singleton_method(:list_zones) { raise CloudflareService::Error.new("cloudflare fora do ar") }
    obj.define_singleton_method(:list_dns_records) { |**| raise CloudflareService::Error.new("cloudflare fora do ar") }
    obj
  end
end
