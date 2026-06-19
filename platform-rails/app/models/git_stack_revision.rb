class GitStackRevision < ApplicationRecord
  belongs_to :git_stack

  scope :recent, -> { order(Arel.sql("COALESCE(deployed_at, created_at) DESC")) }

  def short_sha = sha.to_s.first(12)
end
