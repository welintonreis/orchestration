module AiQuota
  module Refresh
    # Renews an expired OAuth credential.
    #
    # These providers hand back a NEW refresh token on every renewal (rotation),
    # which is why a file-backed credential must be written back to its file: if
    # we kept the new one to ourselves, the CLI that owns that file would be
    # left holding a dead token and would silently stop working. Learned the
    # hard way on 2026-09-01, against ~/.codex/auth.json.
    class Base < Fetch::Base
      class WriteError < StandardError; end

      def call
        payload = renew
        return false if payload.blank?

        account.credential = merge_into(account.credential || {}, payload)
        persist!
        true
      end

      private

      # Provider-specific: the token payload, or nil when renewal failed.
      def renew = raise(NotImplementedError)

      # Provider-specific: writes the payload into that provider's shape.
      def merge_into(_credential, _payload) = raise(NotImplementedError)

      def persist!
        account.credential_source == "file" ? write_file! : account.save!
      end

      # Atomic: write a sibling temp file and rename over the target, so a crash
      # mid-write can't leave the CLI with a truncated credential file.
      def write_file!
        path = account.resolved_path
        raise WriteError, "conta sem caminho de credencial" if path.blank?

        tmp = File.join(File.dirname(path), ".#{File.basename(path)}.#{SecureRandom.hex(4)}")
        File.write(tmp, JSON.pretty_generate(account.credential))
        File.chmod(0o600, tmp)
        File.rename(tmp, path)
        tmp = nil
      ensure
        FileUtils.rm_f(tmp) if tmp
      end
    end
  end
end
