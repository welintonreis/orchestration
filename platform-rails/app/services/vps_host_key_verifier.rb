# Trust-on-first-use host key verifier compatible with Net::SSH 7.x.
# First connection: stores the server's fingerprint on the VpsHost record.
# Subsequent connections: rejects if fingerprint changed (MITM guard).
class VpsHostKeyVerifier
  attr_reader :actual_fingerprint

  def initialize(host)
    @host               = host
    @actual_fingerprint = nil
  end

  # Called by Net::SSH with { key:, key_blob:, fingerprint:, session: }.
  # Return false → Net::SSH raises Net::SSH::Exception("host key verification failed").
  def verify(arguments)
    @actual_fingerprint = arguments[:fingerprint]

    if @host.host_key_fingerprint.blank?
      @host.update_column(:host_key_fingerprint, @actual_fingerprint)
      return true
    end

    @host.host_key_fingerprint == @actual_fingerprint
  rescue => e
    Rails.logger.error("VpsHostKeyVerifier error: #{e.message}")
    false
  end

  # Required by Net::SSH 7 to avoid deprecation warning on custom verifiers.
  def verify_signature
    yield
  end
end
