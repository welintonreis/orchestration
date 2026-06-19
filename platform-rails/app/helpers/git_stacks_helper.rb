module GitStacksHelper
  SYNC_BADGE = {
    "synced"      => ["Synced",      "bg-green-100 dark:bg-green-900/40 text-green-600 dark:text-green-400 border border-green-300 dark:border-green-800/60"],
    "out_of_sync" => ["OutOfSync",   "bg-amber-100 dark:bg-amber-900/40 text-amber-600 dark:text-amber-400 border border-amber-300 dark:border-amber-800/60"],
    "unknown"     => ["Unknown",     "bg-surface-inset text-text-secondary border border-border-subtle"]
  }.freeze

  HEALTH_BADGE = {
    "healthy"     => ["Healthy",     "bg-green-100 dark:bg-green-900/40 text-green-600 dark:text-green-400 border border-green-300 dark:border-green-800/60"],
    "progressing" => ["Progressing", "bg-blue-100 dark:bg-blue-900/40 text-blue-600 dark:text-blue-400 border border-blue-300 dark:border-blue-800/60"],
    "degraded"    => ["Degraded",    "bg-red-100 dark:bg-red-900/40 text-red-600 dark:text-red-400 border border-red-300 dark:border-red-800/60"],
    "missing"     => ["Missing",     "bg-surface-inset text-text-muted border border-border-subtle"],
    "unknown"     => ["Unknown",     "bg-surface-inset text-text-secondary border border-border-subtle"]
  }.freeze

  def sync_status_badge(stack)
    label, klass = SYNC_BADGE.fetch(stack.sync_status, SYNC_BADGE["unknown"])
    content_tag(:span, label, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{klass}")
  end

  def health_badge(stack)
    label, klass = HEALTH_BADGE.fetch(stack.health, HEALTH_BADGE["unknown"])
    content_tag(:span, label, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{klass}")
  end

  # Human one-liner for a single drifted-service entry from drift_detail.
  def drift_state_label(entry)
    case entry["state"]
    when "missing" then "não implantado (existe no Git)"
    when "extra"   then "órfão (existe no Swarm, não no Git)"
    else                "divergente"
    end
  end
end
