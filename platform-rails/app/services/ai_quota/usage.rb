module AiQuota
  # Entry point: give it an account, get a normalized Result.
  module Usage
    FETCHERS   = { "claude" => Fetch::Claude,   "codex" => Fetch::Codex }.freeze
    REFRESHERS = { "claude" => Refresh::Claude, "codex" => Refresh::Codex }.freeze

    module_function

    def for(account, force: false)
      fetcher = FETCHERS[account.provider]
      return Result.error("Sem leitor de quota para #{account.provider}") unless fetcher

      key = cache_key(account)
      Rails.cache.delete(key) if force

      Rails.cache.fetch(key, expires_in: fetcher::CACHE_TTL) { fetch_renewing(account, fetcher) }
    end

    # An expired credential is the one failure worth retrying automatically: the
    # token just aged out and we hold the means to renew it. Any other failure
    # is reported as-is rather than retried into a rate limit.
    def fetch_renewing(account, fetcher)
      result = fetcher.new(account).call
      return record(account, result) if result.ok? || !expired?(result)

      refresher = REFRESHERS[account.provider]
      return record(account, result) unless refresher&.new(account)&.call

      record(account, fetcher.new(account.reload_credential).call)
    rescue StandardError => e
      record(account, Result.error(e.message))
    end

    def expired?(result)
      result.message.to_s.match?(/expirad|reautentiqu|renove/i)
    end

    # The card shows the last error; the sidebar counts healthy accounts. Both
    # read from the record, so a failed fetch has to land there — but never as
    # a validation failure that would hide the real problem behind a 500.
    def record(account, result)
      return result unless account.persisted?

      account.update_columns(
        test_status: result.ok? ? "active" : "error",
        last_error: result.ok? ? nil : result.message,
        last_error_at: result.ok? ? nil : Time.current,
        last_used_at: Time.current
      )
      result
    end

    # Busting on updated_at means a credential refresh (which touches the record
    # or its file) can't be served a stale quota from before it.
    def cache_key(account)
      stamp = account.credential_source == "file" ? file_stamp(account) : account.updated_at.to_i
      "ai_quota/#{account.id}/#{stamp}"
    end

    def file_stamp(account)
      path = account.resolved_path
      path && File.exist?(path) ? File.mtime(path).to_i : 0
    end
  end
end
