require "securerandom"

# Short-lived enrollment credential handed to a brand-new agent in its
# one-liner `docker run` command. Signed (not encrypted — the node name
# isn't a secret) with the same edge_key used to revoke the whole fleet.
# The agent treats it as an opaque string; only the hub parses it.
#
# Single-use isn't tracked separately (no cache/nonce table to keep
# consistent) — the token embeds the node's future uuid, and EdgeNode.uuid
# has a DB-level unique index. EdgeNode.enroll! with that uuid is itself
# the atomic "consume": a replayed token collides on the unique index and
# the enroll transaction rolls back.
class EdgeEnrollmentToken
  TTL = 15.minutes

  def self.generate(node_name:)
    verifier.generate(
      { "name" => node_name, "uuid" => SecureRandom.uuid },
      expires_in: TTL, purpose: "edge-enroll"
    )
  end

  # Returns { "name" => ..., "uuid" => ... } if the token's signature and
  # expiry are valid; nil otherwise. Does NOT check whether it's already
  # been consumed — that's EdgeNode.enroll!'s job (see class comment).
  def self.consume(token)
    verifier.verify(token, purpose: "edge-enroll")
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.edge_key
    AppSetting.get("edge_key") || AppSetting.set("edge_key", SecureRandom.hex(32)).value
  end

  def self.verifier
    ActiveSupport::MessageVerifier.new(edge_key, serializer: JSON, digest: "SHA256")
  end
  private_class_method :verifier
end
