class Environment < ApplicationRecord
  ENDPOINT_TYPES = %w[unix tcp edge kubernetes].freeze

  has_many :environment_group_memberships, dependent: :destroy
  has_many :environment_groups, through: :environment_group_memberships
  has_many :environment_tag_assignments, dependent: :destroy
  has_many :environment_tags, through: :environment_tag_assignments
  has_many :environment_registries, dependent: :destroy
  has_one  :edge_node, dependent: :destroy

  encrypts :kube_token_ciphertext
  encrypts :kube_client_cert_ciphertext
  encrypts :kube_client_key_ciphertext

  validates :name, presence: true, uniqueness: true
  validates :endpoint_type, inclusion: { in: ENDPOINT_TYPES }
  validates :endpoint, presence: true, format: {
    with: /\A(unix:\/\/\/|tcp:\/\/|edge:\/\/).+/,
    message: "must start with unix:///, tcp:// or edge://"
  }, unless: :kubernetes?
  validates :kube_api_url, presence: true, if: :kubernetes?

  before_validation :mirror_kube_api_url_to_endpoint, if: :kubernetes?

  # NOT `scope :active_env, -> { where(active: true).first }` — Rails scopes
  # fall back to returning `all` (an unfiltered Relation) whenever the body
  # returns something falsy, and `.first` returns nil the moment no
  # environment is active. That silently handed callers a Relation instead
  # of nil/a record, which blew up wherever the result was used like a
  # single Environment (`.effective_endpoint`, `.kubernetes?`, ...). A plain
  # class method has no such fallback.
  def self.active_env
    where(active: true).first
  end

  def unix?       = endpoint_type == "unix"
  def tcp?        = endpoint_type == "tcp"
  def edge?       = endpoint_type == "edge"
  def kubernetes? = endpoint_type == "kubernetes"

  def kube_token       = kube_token_ciphertext
  def kube_client_cert = kube_client_cert_ciphertext
  def kube_client_key  = kube_client_key_ciphertext

  # Deactivate self LAST, not first: `update_all(active: false)` writes the
  # DB directly without touching in-memory attributes, so if `self` was
  # already the active row, its own `active` attribute was (and still is)
  # `true` in memory — the follow-up `update!(active: true)` then sees no
  # actual change and skips the write, leaving the DB row it just zeroed
  # out via update_all stuck at false. Net result: activating the
  # already-active environment left NONE active. Setting self first (a
  # real, always-effective write) then clearing every other row avoids the
  # stale-dirty-tracking trap regardless of self's prior state.
  def activate!
    update!(active: true)
    Environment.where.not(id: id).update_all(active: false)
  end

  # Docker screens (containers/images/.../TtydManager) only ever see a
  # unix:// or tcp:// endpoint — for an edge node this resolves the live
  # local proxy address (dialing the tunnel on first use), so none of that
  # code needs to know edge nodes exist at all.
  def effective_endpoint
    return endpoint unless edge? && edge_node.present?
    EdgeTunnelRegistry.instance.proxy_endpoint_for(edge_node)
  end

  def kube_client
    KubeClient.new(
      api_url: kube_api_url, token: kube_token, ca_cert: kube_ca_cert,
      client_cert: kube_client_cert, client_key: kube_client_key
    )
  end

  private

  # `endpoint` stays NOT NULL/format-checked for unix/tcp/edge; kubernetes
  # environments don't use it for anything (KubeClient reads kube_api_url
  # directly) — mirroring keeps the column satisfied without a schema
  # change or a conditional NOT NULL constraint.
  def mirror_kube_api_url_to_endpoint
    self.endpoint = kube_api_url.to_s
  end
end
