class Environment < ApplicationRecord
  ENDPOINT_TYPES = %w[unix tcp edge].freeze

  has_many :environment_group_memberships, dependent: :destroy
  has_many :environment_groups, through: :environment_group_memberships
  has_many :environment_tag_assignments, dependent: :destroy
  has_many :environment_tags, through: :environment_tag_assignments
  has_many :environment_registries, dependent: :destroy
  has_one  :edge_node, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :endpoint_type, inclusion: { in: ENDPOINT_TYPES }
  validates :endpoint, presence: true, format: {
    with: /\A(unix:\/\/\/|tcp:\/\/|edge:\/\/).+/,
    message: "must start with unix:///, tcp:// or edge://"
  }

  scope :active_env, -> { where(active: true).first }

  def unix? = endpoint_type == "unix"
  def tcp?  = endpoint_type == "tcp"
  def edge? = endpoint_type == "edge"

  def activate!
    Environment.update_all(active: false)
    update!(active: true)
  end

  # Docker screens (containers/images/.../TtydManager) only ever see a
  # unix:// or tcp:// endpoint — for an edge node this resolves the live
  # local proxy address (dialing the tunnel on first use), so none of that
  # code needs to know edge nodes exist at all.
  def effective_endpoint
    return endpoint unless edge? && edge_node.present?
    EdgeTunnelRegistry.instance.proxy_endpoint_for(edge_node)
  end
end
