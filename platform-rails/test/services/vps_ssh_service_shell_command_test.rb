require "test_helper"

# The branch order in shell_command decides whether reattaching a terminal
# session gives you your screen back. tmux MUST come first: it is the only
# wrapper here that keeps a screen buffer and repaints it whole on reattach.
# dtach keeps the process but not the picture (SIGWINCH only), which is what
# made v0.9.60 land users on a blank screen. Asserted by running the generated
# snippet through a real /bin/sh with fake tmux/dtach on PATH, so a reorder
# fails here instead of on a host. See
# docs/specs/incident-terminal-vps-selecao.md for the full history.
class VpsSshServiceShellCommandTest < ActiveSupport::TestCase
  def setup
    @dir = Dir.mktmpdir
    @host    = Struct.new(:id, :hostname, :username, :port).new("h1", "example", "root", 22)
    @session = Struct.new(:slot, :token, :vps_host, :terminal_cols, :terminal_rows)
                 .new(0, "tok", @host, 80, 24)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # Fake binaries that echo their name instead of exec'ing a real shell.
  def stub_bin(name, body)
    path = File.join(@dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    FileUtils.chmod(0o755, path)
  end

  # PATH is @dir alone: the real tmux/dtach on this machine must not leak in
  # and decide the branch for us (that bug made an early version of this test
  # pass for the wrong reason).
  def run_snippet
    cmd = VpsSshService.new(@session).send(:shell_command)
    # `exec` would replace the shell; neutralize it so we can see the choice.
    IO.popen({ "PATH" => @dir }, ["/bin/sh", "-c", cmd.gsub("exec ", "")], &:read).strip
  end

  test "tmux wins whenever the host has it — screen survives reattach" do
    stub_bin("tmux",  'echo TMUX')
    stub_bin("dtach", 'echo DTACH')
    assert_equal "TMUX", run_snippet
  end

  test "tmux is started with mouse on so the wheel scrolls the pane" do
    assert_includes VpsSshService.new(@session).send(:shell_command), "set -g mouse on"
  end

  test "dtach is the fallback on a host without tmux" do
    stub_bin("dtach", 'echo DTACH')
    assert_equal "DTACH", run_snippet
  end

  test "abduco is the fallback on a host with neither" do
    stub_bin("abduco", 'echo ABDUCO')
    assert_equal "ABDUCO", run_snippet
  end

  test "slot isolates the session name and dtach socket" do
    svc = VpsSshService.new(@session)
    assert_equal "vps_h1", svc.send(:session_name)
    @session.slot = 2
    assert_equal "vps_h1_s2", svc.send(:session_name)
    assert_equal "/tmp/.vps-h1_s2.dtach", svc.send(:dtach_socket)
  end
end
