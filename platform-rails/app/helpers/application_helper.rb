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
  }.freeze

  def nav_icon(key)
    NAV_ICONS.fetch(key, "").html_safe
  end
end
