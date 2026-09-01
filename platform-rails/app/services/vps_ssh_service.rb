require "net/ssh"
require "shellwords"

# Real SSH terminal to a VPS host (not a container/pod exec) — ported from
# redhusky-remote-ssh's SshConnectionService. Kept as a plain-Ruby thread
# reading the SSH channel and yielding output to the caller (ActionCable's
# transmit), NOT orchestration's ttyd/Rack-hijack transport: ttyd wraps
# `docker exec`/`kubectl exec` into a container, there's no host to point it
# at here.
class VpsSshService
  MAX_INPUT_SIZE = 65_536

  # Thread objects and SSH channels can't be serialized — store in-process.
  # MRI's GIL makes simple hash read/write thread-safe enough here.
  THREADS  = {}
  CHANNELS = {}
  # Latest resize seen per session, applied once the channel finishes
  # connecting (a resize that arrives mid-handshake would otherwise be
  # silently dropped, leaving the remote PTY at a stale width).
  PENDING_RESIZE = {}

  # net-ssh never sets TCP_NODELAY (plain Socket.tcp), so each keystroke to a
  # WAN target pays Nagle + delayed-ACK — up to ~40ms/char. The :proxy option
  # is net-ssh's socket-factory escape hatch; same connect, plus nodelay.
  class NodelaySocketFactory
    def self.open(host, port, options)
      sock = Socket.tcp(host, port, nil, nil, connect_timeout: options[:timeout])
      sock.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      sock
    end
  end

  def initialize(session)
    @session = session
    @host    = session.vps_host
    @tkey    = "t_#{session.token}"
    @ckey    = "c_#{session.token}"
  end

  def connect(cols: nil, rows: nil, &on_data)
    @initial_cols = cols.to_i.positive? ? cols.to_i : nil
    @initial_rows = rows.to_i.positive? ? rows.to_i : nil
    @verifier = VpsHostKeyVerifier.new(@host)
    options   = self.class.build_options(@host, @verifier)
    thread    = Thread.new { run_ssh(options, &on_data) }
    THREADS[@tkey] = thread
    thread
  end

  def send_input(data)
    return if data.nil? || data.bytesize > MAX_INPUT_SIZE
    CHANNELS[@ckey]&.send_data(data)
  rescue => e
    Rails.logger.warn("VpsSshService#send_input error: #{e.message}")
  end

  def resize(cols, rows)
    PENDING_RESIZE[@ckey] = [cols, rows]
    CHANNELS[@ckey]&.send_channel_request(
      "window-change", :long, cols, :long, rows, :long, 0, :long, 0
    )
  rescue => e
    Rails.logger.debug("VpsSshService#resize skipped: #{e.message}")
  ensure
    @session.update_columns(terminal_cols: cols, terminal_rows: rows) rescue nil
  end

  def disconnect
    THREADS.delete(@tkey)&.kill rescue nil
    CHANNELS.delete(@ckey) rescue nil
    PENDING_RESIZE.delete(@ckey) rescue nil
  end

  # Shared by VpsSshService and VpsSftpPool — connection options for a
  # VpsHost, keyed off its SharedCredential.
  def self.build_options(host, verifier)
    credential = host.shared_credential
    raise "No credential configured for host '#{host.name}'." unless credential

    opts = {
      port:               host.port,
      verify_host_key:    verifier,
      timeout:            10,
      non_interactive:    true,
      use_agent:          false,
      keys:               [],
      compression:        false,
      keepalive:          true,
      keepalive_interval: 30,
      proxy:              NodelaySocketFactory,
    }

    case host.auth_method
    when "password"
      opts[:password]     = credential.encrypted_secret
      opts[:auth_methods] = %w[password]
    when "key", "key_with_passphrase"
      # ponytail: key_with_passphrase has no passphrase field on
      # SharedCredential yet (only :encrypted_secret) — add encrypted_passphrase
      # to shared_credentials when a passphrase-protected key is actually needed.
      opts[:key_data]     = [credential.encrypted_secret]
      opts[:auth_methods] = %w[publickey]
    end

    opts
  end

  private

  def run_ssh(options, &on_data)
    Net::SSH.start(@host.hostname, @host.username, **options) do |ssh|
      ssh.open_channel do |ch|
        # Register data handlers FIRST — bash prompt may arrive before exec callback fires
        ch.on_data          { |_, data| on_data&.call(data) }
        ch.on_extended_data { |_, _, data| on_data&.call(data) }
        ch.on_close         { CHANNELS.delete(@ckey); @session.mark_disconnected! rescue nil }

        ch.request_pty(
          term:        "xterm-256color",
          chars_wide:  @initial_cols || @session.terminal_cols || 80,
          chars_high:  @initial_rows || @session.terminal_rows || 24,
          pixels_wide: 0,
          pixels_high: 0,
          modes:       {}
        ) do |_, pty_ok|
          unless pty_ok
            @session.mark_disconnected!(error: "PTY allocation failed")
            ch.close
            next
          end

          # Execute shell wrapper via plain sh (fast, skips profile startup overhead).
          # The inner login shell (zsh -l / bash -l) then loads the user's full environment.
          ch.exec("sh -c #{Shellwords.escape(shell_command)}") do |_, exec_ok|
            unless exec_ok
              @session.mark_disconnected!(error: "Shell exec failed")
              ch.close
              next
            end

            CHANNELS[@ckey] = ch
            if (dims = PENDING_RESIZE[@ckey])
              ch.send_channel_request(
                "window-change", :long, dims[0], :long, dims[1], :long, 0, :long, 0
              )
            end
            @session.mark_connected!
          end
        end
      end

      # Poll every 5ms (not nil/blocking): input is enqueued from the
      # ActionCable worker thread via send_data, but the actual socket flush
      # only happens inside this event loop.
      ssh.loop(0.005) { THREADS.key?(@tkey) }
    end
  rescue Net::SSH::Exception => e
    if e.message == "host key verification failed"
      expected = @host.host_key_fingerprint
      actual   = @verifier&.actual_fingerprint || "unknown"
      msg      = "Host key changed! Expected #{expected}, got #{actual}"
      @session.mark_disconnected!(error: msg)
      Rails.logger.error("SSH host key mismatch [#{@session.token}] #{@host.hostname}: #{msg}")
      ActionCable.server.broadcast(
        "vps_terminal_#{@session.token}",
        output: Base64.strict_encode64(
          "\r\n\x1b[1;31m⚠  SECURITY ALERT: Host key has changed!\x1b[0m\r\n" \
          "Expected : #{expected}\r\n" \
          "Got      : #{actual}\r\n" \
          "Connection refused. If intentional, clear the stored fingerprint on the host settings.\r\n"
        )
      )
    else
      @session.mark_disconnected!(error: e.message) rescue nil
      Rails.logger.error("VpsSshService SSH exception [#{@session.token}]: #{e.message}")
    end
  rescue Net::SSH::AuthenticationFailed => e
    @session.mark_disconnected!(error: "Auth failed: #{e.message}")
    Rails.logger.error("SSH auth failed [#{@session.token}]: #{e.message}")
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::SSH::ConnectionTimeout => e
    @session.mark_disconnected!(error: "Cannot connect: #{e.message}")
  rescue => e
    @session.mark_disconnected!(error: e.message) rescue nil
    Rails.logger.error("VpsSshService [#{@session.token}]: #{e.class}: #{e.message}")
  end

  # Persistent, transparent shell so it survives WebSocket drops and resumes
  # on reconnect. Preference: dtach/abduco (transparent, no altscreen) > tmux
  # (mouse-scroll enabled) > plain shell. Slot isolates concurrent tabs.
  # Login shell prefers zsh (user wants zsh w/ Nerd Font glyphs), falls back
  # to bash — whichever is actually installed on the target host.
  def shell_command
    slot   = @session.slot.to_i
    suffix = slot.positive? ? "_s#{slot}" : ""
    name   = "vps_#{@host.id}#{suffix}"
    sock   = "/tmp/.vps-#{@host.id}#{suffix}.dtach"
    login_shell = "$(command -v zsh || command -v bash) -l"
    <<~SH.strip
      if command -v tmux >/dev/null 2>&1 && tmux has-session -t #{name} 2>/dev/null; then exec tmux new-session -A -s #{name} \\; set -g mouse on;
      elif command -v dtach >/dev/null 2>&1; then exec dtach -A #{sock} -z -r winch #{login_shell};
      elif command -v abduco >/dev/null 2>&1; then exec abduco -A #{name} #{login_shell};
      elif command -v tmux >/dev/null 2>&1; then exec tmux new-session -A -s #{name} \\; set -g mouse on;
      else exec #{login_shell}; fi
    SH
  end
end
