# One AI provider account whose quota the platform tracks.
#
# The credential either lives here (encrypted) or in a CLI's own credential
# file on disk. File-backed accounts exist because the Claude Code / Codex CLIs
# already hold working OAuth credentials on this host and keep refreshing them
# — re-authenticating a second copy would just create two tokens fighting over
# the same refresh chain. When we do refresh a file-backed credential ourselves
# (the CLI hasn't run and the token went stale), we write it back to the file
# so there stays exactly one source of truth.
class AiAccount < ApplicationRecord
  encrypts :credentials

  # Only providers with a working quota fetcher — see AiQuota::Usage.
  PROVIDERS = %w[claude codex].freeze

  SOURCES = %w[inline file].freeze

  # Where each CLI keeps its credential, for the "import local credential" flow.
  KNOWN_CREDENTIAL_FILES = {
    "claude" => "~/.claude/.credentials.json",
    "codex"  => "~/.codex/auth.json"
  }.freeze

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :credential_source, inclusion: { in: SOURCES }
  validates :credential_path, presence: true, if: -> { credential_source == "file" }

  scope :active, -> { where(active: true) }
  scope :by_priority, -> { order(Arel.sql("priority IS NULL, priority ASC, provider ASC")) }

  def label
    name.presence || email.presence || display_name.presence || "#{provider} ##{id}"
  end

  # The raw credential hash, whichever side it lives on. Nil when a file-backed
  # account points at a file that's gone (CLI uninstalled, mount missing) —
  # callers surface that as an error state rather than crashing the page.
  def credential
    @credential ||=
      if credential_source == "file"
        read_credential_file
      else
        credentials.present? ? JSON.parse(credentials) : nil
      end
  rescue JSON::ParserError
    nil
  end

  def credential=(hash)
    @credential = hash
    self.credentials = hash&.to_json
  end

  # After a refresh writes new tokens (to our column or to the CLI's file), the
  # memoized copy is stale — drop it so the retry uses the fresh token.
  def reload_credential
    @credential = nil
    reload if persisted? && credential_source != "file"
    self
  end

  def resolved_path
    File.expand_path(credential_path) if credential_path.present?
  end

  private

  def read_credential_file
    path = resolved_path
    return nil unless path && File.readable?(path)

    JSON.parse(File.read(path))
  end
end
