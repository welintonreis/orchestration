module ApplicationHelper
  # Returns a CSS class string for a container status badge element.
  # Use with `.html_safe` or in a tag helper — the class goes on the badge span.
  def status_badge(status)
    case status.to_s.downcase
    when "running"    then "badge-running"
    when "exited"     then "badge-exited"
    when "paused"     then "badge-paused"
    when "restarting" then "badge-restarting"
    when "created"    then "badge-created"
    when "dead"       then "badge-dead"
    else                   "badge-exited"
    end
  end

  # Returns a Tailwind text color class based on a percentage value.
  # green < 60%, yellow 60-79%, red >= 80%
  def percent_color(pct)
    pct = pct.to_f
    if pct >= 80
      "text-red-400"
    elsif pct >= 60
      "text-yellow-400"
    else
      "text-green-400"
    end
  end

  # Formats a byte count as a human-readable string (e.g. "1.2 GB", "512 MB").
  def human_bytes(bytes)
    bytes = bytes.to_i
    return "0 B" if bytes == 0

    units = %w[B KB MB GB TB PB]
    exp   = (Math.log(bytes) / Math.log(1024)).floor
    exp   = [exp, units.length - 1].min
    value = bytes.to_f / (1024**exp)

    if exp == 0
      "#{value.round} B"
    elsif value >= 100
      "#{value.round} #{units[exp]}"
    else
      "#{"%.1f" % value} #{units[exp]}"
    end
  end

  # Returns a relative time string such as "2 hours ago" or "3 days ago".
  def human_age(time)
    return "—" if time.nil?
    time_ago_in_words(time) + " ago"
  end

  # Sets the page title via content_for and returns nil (call in view, not output directly).
  def page_title(title)
    content_for(:title) { title }
    nil
  end

  # Adds breadcrumb items to content_for(:breadcrumbs).
  # Usage: breadcrumb ["Containers", containers_path], ["Logs", nil]
  def breadcrumb(*items)
    content_for(:breadcrumbs) do
      safe = items.each_with_index.map do |(label, path), i|
        if path && i < items.length - 1
          link_to(label, path, class: "text-gray-500 hover:text-gray-300 transition-colors")
        else
          tag.span(label, class: "text-gray-300")
        end
      end
      safe_join(safe, tag.span(" / ", class: "text-gray-700 mx-1"))
    end
    nil
  end

  # Generates an inline SVG sparkline for an array of HostMetric records.
  # attribute: symbol — e.g. :cpu_percent, :ram_percent
  def sparkline_svg(metrics, attribute, width: 120, height: 20)
    return "".html_safe if metrics.blank?

    values    = metrics.map { |m| m.public_send(attribute).to_f }
    min_val   = [values.min, 0].min
    max_val   = [values.max, 1].max
    range     = (max_val - min_val).nonzero? || 1
    n         = values.size - 1
    n         = 1 if n < 1

    points = values.each_with_index.map do |v, i|
      x = (i.to_f / n * width).round(2)
      y = (height - ((v - min_val) / range * height)).round(2)
      "#{x},#{y}"
    end.join(" ")

    latest = values.last
    color  = latest >= 80 ? "#f87171" : latest >= 60 ? "#facc15" : "#4ade80"

    tag.svg(
      tag.polyline(points: points, fill: "none", stroke: color, "stroke-width": "1.5", "stroke-linejoin": "round"),
      viewBox: "0 0 #{width} #{height}",
      class: "w-full",
      style: "height:#{height}px",
      preserveAspectRatio: "none"
    )
  end

  # Renders a sidebar navigation link with optional icon and Alpine.js-aware collapsed state.
  #
  # icon:               one of the symbol keys defined in NAV_ICONS below
  # sidebar_open_expr:  Alpine.js expression string for the "open" boolean (default "sidebarOpen")
  #
  # Returns an HTML-safe string.
  def nav_link(name, path, icon: nil, sidebar_open_expr: "sidebarOpen")
    active     = request.path == path || (path != root_path && request.path.start_with?(path))
    base_class = "flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors group"
    active_cls = "bg-cyan-900/40 text-cyan-400 border border-cyan-800/60"
    idle_cls   = "text-gray-400 hover:text-white hover:bg-gray-800"
    item_class = [base_class, active ? active_cls : idle_cls].join(" ")

    svg_html = icon ? nav_icon(icon) : ""

    label_html = tag.span(
      name,
      class: "truncate transition-opacity duration-150",
      "x-bind:class" => "#{sidebar_open_expr} ? 'opacity-100' : 'opacity-0 hidden'"
    )

    link_to path, class: item_class, title: name do
      (svg_html + label_html).html_safe
    end
  end

  private

  NAV_ICONS = {
    dashboard: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/>
      </svg>
    SVG
    containers: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"/>
      </svg>
    SVG
    images: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
      </svg>
    SVG
    volumes: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4"/>
      </svg>
    SVG
    networks: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
      </svg>
    SVG
    swarm: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"/>
      </svg>
    SVG
    git: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
      </svg>
    SVG
    environments: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"/>
      </svg>
    SVG
    alerts: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
      </svg>
    SVG
    users: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/>
      </svg>
    SVG
    audit: <<~SVG,
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.5">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"/>
      </svg>
    SVG
  }.freeze

  def nav_icon(key)
    NAV_ICONS.fetch(key, "").html_safe
  end
end
