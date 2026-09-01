require "net/ssh"
require "net/sftp"

# Reuses one SSH+SFTP connection per VpsTerminalSession's host for the file
# browser — ported from redhusky-remote-ssh's SftpSessionPool. Entries are
# per-process, serialized with a per-entry mutex (SFTP is not safe for
# concurrent requests). Idle entries reaped lazily on any acquire.
#
# NOT for downloads/archives — those stream inside a response-body enumerator
# the client can abandon mid-transfer; parking the pool mutex there would
# wedge the entry forever. Streaming actions open their own throwaway
# connection via VpsSshService.build_options.
class VpsSftpPool
  ENTRIES      = {}
  LOCK         = Mutex.new
  IDLE_TIMEOUT = 300 # seconds
  MAX_ENTRIES  = 20

  class << self
    # Yields a live SFTP session for this VpsHost, connecting on demand.
    def with(host)
      entry = acquire(host)
      entry[:mutex].synchronize do
        ensure_alive(entry, host)
        result = yield entry[:sftp]
        entry[:last_used] = now
        result
      end
    end

    # Yields the underlying SSH session (for exec: rm -rf, cp, mv, tar).
    def with_ssh(host)
      entry = acquire(host)
      entry[:mutex].synchronize do
        ensure_alive(entry, host)
        result = yield entry[:ssh]
        entry[:last_used] = now
        result
      end
    end

    # Close and forget a host's entry.
    def release(host_id)
      entry = LOCK.synchronize { ENTRIES.delete(host_id) }
      close_entry(entry)
    end

    private

    def acquire(host)
      LOCK.synchronize do
        reap_idle
        ENTRIES[host.id] ||= { mutex: Mutex.new, ssh: nil, sftp: nil, last_used: now }
      end
    end

    def ensure_alive(entry, host)
      if entry[:ssh].nil? || entry[:ssh].closed? || now - entry[:last_used] > IDLE_TIMEOUT
        close_entry(entry)
        entry[:ssh]  = Net::SSH.start(host.hostname, host.username,
                                       **VpsSshService.build_options(host, VpsHostKeyVerifier.new(host)))
        entry[:sftp] = entry[:ssh].sftp # net-sftp: memoized subsystem, waits until open
      end
    end

    def reap_idle
      cutoff = now - IDLE_TIMEOUT
      ENTRIES.select { |_, e| e[:last_used] < cutoff }.keys.each { |id| drop(id) }
      while ENTRIES.size > MAX_ENTRIES
        id, = ENTRIES.min_by { |_, e| e[:last_used] }
        break unless id && drop(id)
      end
    end

    def drop(host_id)
      entry = ENTRIES[host_id]
      return false unless entry && entry[:mutex].try_lock
      begin
        close_entry(entry)
        ENTRIES.delete(host_id)
        true
      ensure
        entry[:mutex].unlock
      end
    end

    def close_entry(entry)
      entry&.dig(:ssh)&.close
    rescue StandardError
      nil
    ensure
      entry[:ssh] = entry[:sftp] = nil if entry
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
