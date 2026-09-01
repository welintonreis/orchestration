require "test_helper"

# The branch order in shell_command is the whole fix for "can't select/copy in
# the VPS terminal": tmux with `mouse on` eats the drag. Asserted by actually
# running the generated snippet through /bin/sh with fake tmux/dtach on PATH,
# so a reorder or a broken `has-session` guard fails here instead of on a host.
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

  def run_snippet
    cmd = VpsSshService.new(@session).send(:shell_command)
    # `exec` would replace the shell; neutralize it so we can see the choice.
    out = IO.popen({ "PATH" => @dir }, ["/bin/sh", "-c", cmd.gsub("exec ", "")], &:read)
    out.strip
  end

  test "prefers dtach over tmux when no tmux session exists yet" do
    stub_bin("tmux",  'case "$1" in has-session) exit 1;; esac; echo TMUX')
    stub_bin("dtach", 'echo DTACH')
    assert_equal "DTACH", run_snippet
  end

  test "an existing tmux session for this slot still wins" do
    stub_bin("tmux",  'case "$1" in has-session) exit 0;; esac; echo TMUX')
    stub_bin("dtach", 'echo DTACH')
    assert_equal "TMUX", run_snippet
  end

  test "falls back to tmux on a host without dtach" do
    stub_bin("tmux", 'case "$1" in has-session) exit 1;; esac; echo TMUX')
    assert_equal "TMUX", run_snippet
  end

  test "slot isolates the session name and dtach socket" do
    svc = VpsSshService.new(@session)
    assert_equal "vps_h1", svc.send(:session_name)
    @session.slot = 2
    assert_equal "vps_h1_s2", svc.send(:session_name)
    assert_equal "/tmp/.vps-h1_s2.dtach", svc.send(:dtach_socket)
  end
end
