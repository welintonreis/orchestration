require "test_helper"

class VpsTerminalSessionTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    credential = SharedCredential.create!(name: "vps-session-test", credential_type: "password",
                                          username: "root", encrypted_secret: "s3cr3t")
    @host = VpsHost.create!(name: "vps-session-test", hostname: "127.0.0.1", port: 22,
                            username: "root", auth_method: "password", shared_credential: credential)
    @session = VpsTerminalSession.create!(user: users(:admin_user), vps_host: @host, status: "connecting")
  end

  # UI status ("Conectado") comes from the ActionCable subscribe handshake,
  # which fires before SSH auth/PTY/exec run — mark_connected!/disconnected!
  # must push the real backend outcome down the same stream, or a slow/failed
  # SSH handshake leaves the label lying with a blank screen behind it.
  test "mark_connected! broadcasts the connected status" do
    assert_broadcast_on("vps_terminal_#{@session.token}", status: "connected") do
      @session.mark_connected!
    end
  end

  test "mark_disconnected! with an error broadcasts status and message" do
    assert_broadcast_on("vps_terminal_#{@session.token}", status: "error", message: "boom") do
      @session.mark_disconnected!(error: "boom")
    end
  end
end
