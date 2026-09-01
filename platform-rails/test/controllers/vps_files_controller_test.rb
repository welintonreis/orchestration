require "test_helper"

class VpsFilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin_user)
    credential = SharedCredential.create!(name: "vps-files-test", credential_type: "password",
                                          username: "root", encrypted_secret: "s3cr3t")
    @host = VpsHost.create!(name: "vps-files-test", hostname: "127.0.0.1", port: 22,
                            username: "root", auth_method: "password", shared_credential: credential)
  end

  # The page is painted by vps_file_browser_controller.js from the JSON of this
  # same action, so the HTML render has no business opening an SSH connection —
  # a dead host must still answer a page (with the skeleton), not hang on a
  # handshake whose result the response then threw away.
  test "GET index renders the shell without an SFTP handshake" do
    with_sftp(dead_pool) do
      get vps_host_files_url(@host)
      assert_response :success
      assert_select "[data-vps-file-browser-target='list'] [aria-busy='true']"
    end
  end

  test "GET index as JSON lists the directory" do
    with_sftp(live_pool) do
      get vps_host_files_url(@host, format: :json)
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "/root", body["path"]
      assert_equal [ "notes.txt" ], body["entries"].map { |e| e["name"] }
    end
  end

  test "GET index as JSON reports the connection failure instead of raising" do
    with_sftp(dead_pool) do
      get vps_host_files_url(@host, format: :json)
      assert_response :unprocessable_entity
      assert_match "ssh fora do ar", JSON.parse(response.body)["error"]
    end
  end

  private

  # with_stub can't be used here: VpsSftpPool.with takes the block that does
  # the actual work, and with_stub doesn't forward blocks.
  def with_sftp(handler)
    orig = VpsSftpPool.method(:with)
    VpsSftpPool.define_singleton_method(:with) { |_host, &blk| handler.call(&blk) }
    yield
  ensure
    VpsSftpPool.define_singleton_method(:with, orig)
  end

  def dead_pool
    ->(&_blk) { raise "ssh fora do ar" }
  end

  def live_pool
    ->(&blk) { blk.call(fake_sftp) }
  end

  def fake_sftp
    attrs = Object.new
    attrs.define_singleton_method(:size)        { 5 }
    attrs.define_singleton_method(:mtime)       { 1_756_720_800 }
    attrs.define_singleton_method(:permissions) { 0o100644 }

    entry = Object.new
    entry.define_singleton_method(:name)       { "notes.txt" }
    entry.define_singleton_method(:directory?) { false }
    entry.define_singleton_method(:attributes) { attrs }

    home = Object.new
    home.define_singleton_method(:name) { "/root" }

    dir = Object.new
    dir.define_singleton_method(:entries) { |*| [ entry ] }

    sftp = Object.new
    sftp.define_singleton_method(:realpath!) { |*| home }
    sftp.define_singleton_method(:dir)       { dir }
    sftp
  end
end
