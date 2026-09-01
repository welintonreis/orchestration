module AiQuota
  # Adopts the credentials the CLIs on this host already hold.
  #
  # Phase 1 deliberately has no interactive OAuth flow: logging in again would
  # mint a second credential for the same account, and since these providers
  # rotate refresh tokens, the two copies would invalidate each other. Pointing
  # at the CLI's file keeps one credential with one owner.
  module ImportLocal
    module_function

    # Returns the accounts that exist afterwards for the readable files, so
    # running it twice is a no-op rather than a duplicate.
    def call
      AiAccount::KNOWN_CREDENTIAL_FILES.filter_map do |provider, path|
        expanded = File.expand_path(path)
        next unless File.readable?(expanded)

        account = AiAccount.find_or_initialize_by(provider: provider, credential_path: expanded)
        account.credential_source = "file"
        account.name ||= identity_for(provider, expanded)
        account.save!
        account
      end
    end

    # Best-effort label so the card isn't just "claude #1". Never let a
    # malformed file stop the import.
    def identity_for(provider, path)
      data = JSON.parse(File.read(path))
      case provider
      when "claude" then data.dig("claudeAiOauth", "subscriptionType")
      # Codex's file has only an opaque account_id, which reads worse on a card
      # than nothing — the first fetch adopts the real email from the endpoint.
      when "codex"  then nil
      end
    rescue StandardError
      nil
    end
  end
end
