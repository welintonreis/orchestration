require "test_helper"

class SeaweedfsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin_user) }

  # index must not talk to the filer: load_config/list_buckets/list_objects are
  # three serial HTTP calls, and they used to run before the first byte.
  test "GET index renders the shell without calling the filer" do
    with_filer(:explode) do
      get seaweedfs_url
      assert_response :success
      assert_select "turbo-frame#seaweedfs-content[src]"
      assert_select "[aria-busy='true']"
    end
  end

  test "GET rows renders the bucket list and the explorer" do
    with_filer(:live) do
      get rows_seaweedfs_url
      assert_response :success
      assert_select "turbo-frame#seaweedfs-content"
      assert_select "turbo-frame#seaweedfs-content[src]", false
      assert_match "backups", response.body
      assert_match "dump.sql", response.body
    end
  end

  # A bucket/prefix link inside rows navigates back to index inside the frame;
  # that must render the rows, not a nested frame that never fetches.
  test "GET index as a turbo-frame request renders the rows" do
    with_filer(:live) do
      get seaweedfs_url, headers: { "Turbo-Frame" => "seaweedfs-content" }
      assert_response :success
      assert_select "turbo-frame#seaweedfs-content[src]", false
      assert_match "backups", response.body
    end
  end

  # SeaweedfsService already swallows the connection error and answers empty —
  # rows has to render that as the empty state, not blow up.
  test "GET rows survives a filer that is down" do
    with_filer(:down) do
      get rows_seaweedfs_url
      assert_response :success
      assert_match "Nenhum bucket", response.body
    end
  end

  private

  # SeaweedfsService talks to the filer over HTTP with a 2s timeout per host —
  # unstubbed, every test would pay it three times over.
  def with_filer(mode)
    stubs = case mode
    when :explode
      { load_config: -> { raise "filer fora do ar" }, list_buckets: -> { raise "filer fora do ar" },
        list_objects: -> { raise "filer fora do ar" } }
    when :down
      { load_config: -> { { "identities" => [] } }, list_buckets: -> { [] },
        list_objects: -> { { "Entries" => [] } } }
    else
      { load_config: -> { { "identities" => [] } }, list_buckets: -> { %w[backups media] },
        list_objects: -> { { "Entries" => [ { "name" => "dump.sql", "rel_path" => "dump.sql",
                                              "is_dir" => false, "size" => 12, "mime" => "text/plain",
                                              "mtime" => "2026-09-01T10:00:00" } ] } } }
    end
    originals = stubs.keys.to_h { |m| [ m, SeaweedfsService.method(m) ] }
    stubs.each { |m, body| SeaweedfsService.define_singleton_method(m) { |*| body.call } }
    yield
  ensure
    originals.each { |m, orig| SeaweedfsService.define_singleton_method(m, orig) }
  end
end
