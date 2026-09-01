module AiQuotaHelper
  BAR_COLORS = {
    green:  "bg-green-500",
    yellow: "bg-amber-500",
    red:    "bg-red-500"
  }.freeze

  BADGE_COLORS = { green: :green, yellow: :yellow, red: :red }.freeze

  def quota_bar_color(quota) = BAR_COLORS.fetch(quota.color, "bg-surface-active")

  def quota_badge_color(quota) = BADGE_COLORS.fetch(quota.color, :gray)

  # "3d 4h", "5h 20m", "12m" — the same shape the provider dashboards use, and
  # short enough to sit on one line next to the bar.
  def quota_countdown(reset_at)
    return nil if reset_at.blank?

    seconds = (reset_at - Time.current).to_i
    return "agora" if seconds <= 0

    days, rest = seconds.divmod(86_400)
    hours, rest = rest.divmod(3_600)
    minutes = rest / 60

    return "#{days}d #{hours}h" if days.positive?
    return "#{hours}h #{minutes}m" if hours.positive?

    "#{minutes}m"
  end

  # Absolute time as a second line, because a countdown alone doesn't tell you
  # whether "in 14h" lands tonight or tomorrow morning.
  def quota_reset_at(reset_at)
    return nil if reset_at.blank?

    local = reset_at.in_time_zone
    prefix =
      if local.to_date == Date.current then "Hoje"
      elsif local.to_date == Date.current.tomorrow then "Amanhã"
      else local.strftime("%d/%m")
      end

    "#{prefix}, #{local.strftime('%H:%M')}"
  end

  def quota_usage_label(quota)
    return "#{quota.used} usado · ilimitado" if quota.unlimited
    return "#{number_with_delimiter(quota.used)} / #{number_with_delimiter(quota.total)}" if quota.total.to_i.positive?

    number_with_delimiter(quota.used)
  end

  # Inline SVG rather than a charting gem: it's a polyline of at most 48 points
  # with no axes, legend or interaction. A dependency for this would be all cost
  # and no benefit.
  def quota_sparkline(points, width: 96, height: 20)
    return nil if points.size < 2

    values = points.map { |(_, pct)| pct.to_i.clamp(0, 100) }
    step = width.to_f / (values.size - 1)
    # SVG y grows downward, so a full quota has to sit at the top.
    coords = values.each_with_index.map { |v, i| "#{(i * step).round(1)},#{(height - (v / 100.0 * height)).round(1)}" }

    tag.svg(width: width, height: height, viewBox: "0 0 #{width} #{height}",
            class: "overflow-visible", aria_hidden: "true") do
      tag.polyline(points: coords.join(" "), fill: "none", stroke: "currentColor",
                   stroke_width: "1.5", stroke_linejoin: "round", stroke_linecap: "round")
    end
  end

  def ai_provider_label(provider)
    { "claude" => "Claude", "codex" => "Codex" }.fetch(provider, provider.to_s.titleize)
  end
end
