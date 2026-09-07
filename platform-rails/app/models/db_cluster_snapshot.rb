class DbClusterSnapshot < ApplicationRecord
  # Method, not `scope` — a scope silently falls back to returning `all`
  # when its block returns nil/false (empty result), which would make
  # growth_pct in DbClusterInspectorService treat "no baseline yet" as a
  # truthy relation instead of nil.
  def self.nearest_to(server, db, target_time)
    where(server: server, database_name: db)
      .order(Arel.sql("ABS(EXTRACT(EPOCH FROM (captured_at - '#{target_time.iso8601}')))"))
      .first
  end
end
