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

  # Sidebar link used in layout — supports collapsible sidebar + "em breve" items.
  # open:  Alpine.js variable name for sidebar open state (default "sb")
  # soon:  renders as disabled with "em breve" badge
  # icon:  symbol key in SIDEBAR_ICONS hash
  def sidebar_link(name, path, icon: nil, open: "sb", soon: false, exact: false)
    active = if exact
      !soon && path != "#" && request.path == path
    else
      !soon && path != "#" && (request.path == path || (path != root_path && request.path.start_with?(path + "/")))
    end

    icon_html = sidebar_icon(icon).html_safe

    if soon
      tag.div(class: "flex items-center gap-2.5 px-3 py-1.5 text-sm text-gray-700 cursor-not-allowed select-none") do
        tag.span(icon_html.html_safe, class: "flex-shrink-0 w-5 h-5 flex items-center justify-center opacity-40") +
        tag.span(name, class: "flex-1 truncate transition-all", "x-bind:class" => "#{open} ? 'opacity-100' : 'opacity-0 pointer-events-none'") +
        tag.span("em breve", class: "text-[9px] bg-gray-800 text-gray-600 px-1.5 py-0.5 rounded transition-all", "x-bind:class" => "#{open} ? 'opacity-100' : 'opacity-0'")
      end
    else
      base   = "flex items-center gap-2.5 px-3 py-1.5 rounded-lg text-sm transition-colors"
      active_cls = "bg-red-950/50 text-red-400 border border-red-900/60"
      idle_cls   = "text-gray-400 hover:text-gray-100 hover:bg-gray-800/70"

      link_to path, class: "#{base} #{active ? active_cls : idle_cls}", title: name do
        tag.span(icon_html.html_safe, class: "flex-shrink-0 w-5 h-5 flex items-center justify-center") +
        tag.span(name, class: "flex-1 truncate transition-all", "x-bind:class" => "#{open} ? 'opacity-100' : 'opacity-0 pointer-events-none'")
      end
    end
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

  # Untitled UI icons — stroke-width:2, round caps/joins, 24x24 viewBox
  UUI_SVG_ATTRS = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"'.freeze

  SIDEBAR_ICONS = {
    home:       %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M13.5 8.183V4.817q0-.357.234-.587t.58-.23h4.88q.347 0 .576.23t.23.587v3.366q0 .358-.234.587q-.234.23-.58.23h-4.88q-.346 0-.576-.23t-.23-.587M4 11.2V4.8q0-.34.234-.57t.58-.23h4.88q.347 0 .576.23t.23.57v6.4q0 .34-.234.57t-.58.23h-4.88q-.346 0-.576-.23T4 11.2m9.5 8v-6.4q0-.34.234-.57t.58-.23h4.88q.347 0 .576.23t.23.57v6.4q0 .34-.234.57t-.58.23h-4.88q-.346 0-.576-.23t-.23-.57M4 19.183v-3.366q0-.357.234-.587t.58-.23h4.88q.347 0 .576.23t.23.587v3.366q0 .358-.234.587q-.234.23-.58.23h-4.88q-.346 0-.576-.23T4 19.183M5 11h4.5V5H5zm9.5 8H19v-6h-4.5zm0-11H19V5h-4.5zM5 19h4.5v-3H5zm4.5-3"/></svg>),
    dashboard:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M9 8.5a1 1 0 1 1-2 0a1 1 0 0 1 2 0M6 13a1 1 0 1 0 0-2a1 1 0 0 0 0 2m12 0a1 1 0 1 0 0-2a1 1 0 0 0 0 2m-2-3.5a1 1 0 1 0 0-2a1 1 0 0 0 0 2" opacity=".5"/><path fill="currentColor" d="m15.943 10.498l-4.055 4.505A2 2 0 0 0 10 17h4a2 2 0 0 0-.603-1.431l3.66-4.067a.75.75 0 1 0-1.114-1.004M5 15.25a.75.75 0 0 0 0 1.5h1.5a.75.75 0 0 0 0-1.5zm14.75.75a.75.75 0 0 0-.75-.75h-1.5a.75.75 0 0 0 0 1.5H19a.75.75 0 0 0 .75-.75m-7-10a.75.75 0 0 0-1.5 0v1.5a.75.75 0 0 0 1.5 0z"/><path fill="currentColor" d="M12 3.25C6.063 3.25 1.25 8.063 1.25 14c0 1.498.307 2.927.862 4.224l.005.012c.215.502.363.848.817 1.332c.183.195.439.39.677.548c.238.157.519.315.77.407c.624.227 1.168.227 1.937.227h11.364c.769 0 1.313 0 1.937-.227c.252-.092.532-.25.77-.407s.494-.353.677-.548c.454-.484.603-.83.817-1.332l.005-.012c.555-1.297.862-2.726.862-4.224c0-5.937-4.813-10.75-10.75-10.75M2.75 14a9.25 9.25 0 0 1 18.5 0c0 1.292-.264 2.52-.741 3.634c-.204.477-.267.62-.536.907c-.071.075-.22.197-.41.323c-.19.125-.36.214-.458.25c-.352.128-.632.136-1.502.136H6.397c-.87 0-1.15-.008-1.502-.136a2.6 2.6 0 0 1-.458-.25a2.6 2.6 0 0 1-.41-.323c-.269-.287-.332-.43-.536-.907A9.2 9.2 0 0 1 2.75 14"/></svg>),
    stacks:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M20.5 7.278 12 12m0 0L3.5 7.278M12 12v9.5m9-5.441V7.942c0-.343 0-.514-.05-.667a1 1 0 0 0-.215-.364c-.109-.119-.258-.202-.558-.368l-7.4-4.111c-.284-.158-.425-.237-.575-.267a1 1 0 0 0-.403 0c-.15.03-.292.11-.576.267l-7.4 4.11c-.3.167-.45.25-.558.369a1 1 0 0 0-.215.364C3 7.428 3 7.599 3 7.942v8.117c0 .342 0 .514.05.666a1 1 0 0 0 .215.364c.109.119.258.202.558.368l7.4 4.111c.284.158.425.237.576.268.133.027.27.027.402 0 .15-.031.292-.11.576-.268l7.4-4.11c.3-.167.45-.25.558-.369a.999.999 0 0 0 .215-.364c.05-.152.05-.324.05-.666ZM16.5 9.5l-9-5"/></svg>),
    services:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="currentColor" d="m22.505 11.637l-5.989-3.5a1 1 0 0 0-1.008-.001l-6.011 3.5A1 1 0 0 0 9 12.5v7a1 1 0 0 0 .497.864l6.011 3.5A.96.96 0 0 0 16 24c.174 0 .36-.045.516-.137l5.989-3.5A1 1 0 0 0 23 19.5v-7a1 1 0 0 0-.495-.863m-6.494-1.48l4.007 2.343l-4.007 2.342l-4.023-2.342zM11 14.24l4 2.33v4.685l-4-2.33zm6 7.025v-4.683l4-2.338v4.683z"/><path fill="currentColor" d="M16 1a1 1 0 0 0-.504.136l-12 7A1 1 0 0 0 3 9v14a1 1 0 0 0 .496.864l12 7a1 1 0 0 0 1.008 0l11-6.417l-1.008-1.727L16 28.842L5 22.426V9.575l11-6.417l11 6.416V17h2V9a1 1 0 0 0-.496-.864l-12-7A1 1 0 0 0 16 1"/></svg>),
    containers: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 256 256"><path d="M0 0h256v256H0z" fill="none"/><path fill="currentColor" d="M236.4 70.65L130.2 40.31a8 8 0 0 0-3.33-.23L21.74 55.1A16.08 16.08 0 0 0 8 70.94v114.12a16.08 16.08 0 0 0 13.74 15.84l105.13 15a8.5 8.5 0 0 0 1.13.1a8 8 0 0 0 2.2-.31l106.2-30.34A16.07 16.07 0 0 0 248 170V86a16.07 16.07 0 0 0-11.6-15.35M96 120H80V62.94l40-5.72v141.56l-40-5.72V136h16a8 8 0 0 0 0-16M24 70.94l40-5.72V120H48a8 8 0 0 0 0 16h16v54.78l-40-5.72Zm112 126.45V58.61L232 86v84Z"/></svg>),
    images:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 16 16"><path d="M0 0h16v16H0z" fill="none"/><path fill="currentColor" d="M8 0C3.6 0 0 3.6 0 8s3.6 8 8 8s8-3.6 8-8s-3.6-8-8-8m7 8c0 1.1-.2 2.1-.7 3l-2.7-1.2c.2-.6.4-1.2.4-1.8c0-2.2-1.8-4-4-4c-.5 0-.9.1-1.4.3L5.4 1.5c.6-.2 1.2-.4 1.8-.5l.3 3H8V1c3.9 0 7 3.1 7 7M8 5c1.7 0 3 1.3 3 3s-1.3 3-3 3s-3-1.3-3-3s1.3-3 3-3M1 8c0-1.1.2-2.1.7-3l2.7 1.2C4.2 6.8 4 7.4 4 8c0 2.2 1.8 4 4 4c.5 0 .9-.1 1.4-.3l1.2 2.8c-.6.2-1.2.4-1.8.5l-.3-3H8v3c-3.9 0-7-3.1-7-7"/><path fill="currentColor" d="M10 8a2 2 0 1 1-3.999.001A2 2 0 0 1 10 8"/></svg>),
    networks:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 256 256"><path d="M0 0h256v256H0z" fill="none"/><path fill="currentColor" d="M232 114h-98V86h10a14 14 0 0 0 14-14V40a14 14 0 0 0-14-14h-32a14 14 0 0 0-14 14v32a14 14 0 0 0 14 14h10v28H24a6 6 0 0 0 0 12h34v36H48a14 14 0 0 0-14 14v32a14 14 0 0 0 14 14h32a14 14 0 0 0 14-14v-32a14 14 0 0 0-14-14H70v-36h116v18a6 6 0 0 0 12 0v-18h34a6 6 0 0 0 0-12M110 72V40a2 2 0 0 1 2-2h32a2 2 0 0 1 2 2v32a2 2 0 0 1-2 2h-32a2 2 0 0 1-2-2M82 176v32a2 2 0 0 1-2 2H48a2 2 0 0 1-2-2v-32a2 2 0 0 1 2-2h32a2 2 0 0 1 2 2m138.24-3.76L200.48 192l19.76 19.76a6 6 0 1 1-8.48 8.48L192 200.48l-19.76 19.76a6 6 0 0 1-8.48-8.48L183.52 192l-19.76-19.76a6 6 0 0 1 8.48-8.48L192 183.52l19.76-19.76a6 6 0 0 1 8.48 8.48"/></svg>),
    volumes:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 36 36"><path d="M0 0h36v36H0z" fill="none"/><path fill="currentColor" d="M8 17.58a32.4 32.4 0 0 0 6.3.92a4.1 4.1 0 0 1 .92-1.37a31 31 0 0 1-7.22-1Z"/><path fill="currentColor" d="M6 28V8.19c.34-.76 4.31-2.11 11-2.11s10.67 1.35 11 2v.3c-.82.79-4.58 2.05-11.11 2.05A33.5 33.5 0 0 1 8 9.44v1.44a35.6 35.6 0 0 0 8.89 1c4.29 0 8.8-.58 11.11-1.82v5.07a5.3 5.3 0 0 1-1.81.88H30V8.12c0-3.19-8.17-4-13-4s-13 .85-13 4V28c0 2.63 5.39 3.68 10 4v-2c-4.87-.34-7.72-1.38-8-2"/><path fill="currentColor" d="M8 24.28a31.3 31.3 0 0 0 6 .89v-1.4a29 29 0 0 1-6-.93Z"/><path fill="currentColor" d="M32 18H18a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V20a2 2 0 0 0-2-2M18 32V20h14v12Z"/><path fill="currentColor" d="M21 21.7a.7.7 0 0 0-.7.7v7.49a.7.7 0 0 0 1.4 0V22.4a.7.7 0 0 0-.7-.7"/><path fill="currentColor" d="M25 21.82a.7.7 0 0 0-.7.7V30a.7.7 0 1 0 1.4 0v-7.48a.7.7 0 0 0-.7-.7"/><path fill="currentColor" d="M29 21.7a.7.7 0 0 0-.7.7v7.49a.7.7 0 1 0 1.4 0V22.4a.7.7 0 0 0-.7-.7"/></svg>),
    configs:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M12 18H4v-8h16v2.078a7 7 0 0 1 2 .603V10a2 2 0 0 0-2-2l-1.488-.015l-5.302-3.43A1.96 1.96 0 0 0 14 3a2.03 2.03 0 0 0-1-1.721V0h-1v2a1 1 0 1 1-1 1h-1a1.96 1.96 0 0 0 .796 1.56L5.5 7.984L4 8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h8.08a7 7 0 0 1-.08-1.003A7 7 0 0 1 12 18m-.005-13.026L12 5c.006 0 .01-.027.017-.027L17 8H7Z"/><path fill="currentColor" d="M15 13.26V12a1 1 0 0 0-2 0v3.408a7 7 0 0 1 2-2.148M18 11a1 1 0 0 0-1 1v.294A7 7 0 0 1 19 12a1 1 0 0 0-1-1M6 11a1 1 0 0 0-1 1v4a1 1 0 0 0 2 0v-4a1 1 0 0 0-1-1m4 0a1 1 0 0 0-1 1v4a1 1 0 0 0 2 0v-4a1 1 0 0 0-1-1m13.879 9.319l-1.07-.83a4 4 0 0 0 .04-.49a2.6 2.6 0 0 0-.04-.49l1.06-.83a.26.26 0 0 0 .06-.32l-1-1.73a.25.25 0 0 0-.31-.11l-1.239.5a3.4 3.4 0 0 0-.85-.49l-.19-1.319a.24.24 0 0 0-.24-.21h-1.998a.26.26 0 0 0-.25.21l-.19 1.32a4 4 0 0 0-.85.49l-1.239-.5a.26.26 0 0 0-.31.11l-1 1.73a.25.25 0 0 0 .06.32l1.06.829a4 4 0 0 0 0 .98l-1.06.83a.26.26 0 0 0-.06.32l1 1.73a.25.25 0 0 0 .31.11l1.24-.5a3.4 3.4 0 0 0 .849.49l.19 1.319a.25.25 0 0 0 .25.21H20.1a.26.26 0 0 0 .25-.21l.19-1.32a3.7 3.7 0 0 0 .839-.49l1.25.5a.26.26 0 0 0 .31-.11l.999-1.73a.26.26 0 0 0-.06-.32m-4.758.18a1.5 1.5 0 1 1 1.5-1.5a1.497 1.497 0 0 1-1.5 1.5"/></svg>),
    secrets:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M17 10V8A5 5 0 0 0 7 8v2m5 4.5v2M8.8 21h6.4c1.68 0 2.52 0 3.162-.327a3 3 0 0 0 1.311-1.311C20 18.72 20 17.88 20 16.2v-1.4c0-1.68 0-2.52-.327-3.162a3 3 0 0 0-1.311-1.311C17.72 10 16.88 10 15.2 10H8.8c-1.68 0-2.52 0-3.162.327a3 3 0 0 0-1.311 1.311C4 12.28 4 13.12 4 14.8v1.4c0 1.68 0 2.52.327 3.162a3 3 0 0 0 1.311 1.311C6.28 21 7.12 21 8.8 21Z"/></svg>),
    git:        %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="#e64a19" d="M13.172 2.828L11.78 4.22l1.91 1.91l2 2A2.986 2.986 0 0 1 20 10.81a3.25 3.25 0 0 1-.31 1.31l2.06 2a2.68 2.68 0 0 1 3.37.57a2.86 2.86 0 0 1 .88 2.117a3.02 3.02 0 0 1-.856 2.109A2.9 2.9 0 0 1 23 19.81a2.93 2.93 0 0 1-2.13-.87a2.694 2.694 0 0 1-.56-3.38l-2-2.06a3 3 0 0 1-.31.12V20a3 3 0 0 1 1.44 1.09a2.92 2.92 0 0 1 .56 1.72a2.88 2.88 0 0 1-.878 2.128a2.98 2.98 0 0 1-2.048.871a2.981 2.981 0 0 1-2.514-4.719A3 3 0 0 1 16 20v-6.38a2.96 2.96 0 0 1-1.44-1.09a2.9 2.9 0 0 1-.56-1.72a2.9 2.9 0 0 1 .31-1.31l-3.9-3.9l-7.579 7.572a4 4 0 0 0-.001 5.658l10.342 10.342a4 4 0 0 0 5.656 0l10.344-10.344a4 4 0 0 0 0-5.656L18.828 2.828a4 4 0 0 0-5.656 0"/></svg>),
    sub:        '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-gray-600" fill="currentColor" viewBox="0 0 8 8"><circle cx="4" cy="4" r="2"/></svg>',
  }.freeze

  # Untitled UI action icons (used in table rows, buttons, etc.)
  ACTION_ICONS = {
    play:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M5 4.99c0-.972 0-1.457.202-1.725a1 1 0 0 1 .738-.395c.335-.02.74.25 1.548.788l10.515 7.01c.668.446 1.002.668 1.118.949a1 1 0 0 1 0 .766c-.116.28-.45.503-1.118.948l-10.515 7.01c-.809.54-1.213.809-1.548.789a1 1 0 0 1-.738-.395C5 20.467 5 19.98 5 19.01V4.99Z"/></svg>),
    stop:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M6 5h12a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z"/></svg>),
    restart:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M21 10s-2.005-2.732-3.634-4.362a9 9 0 1 0 2.282 8.862M21 10V4m0 6h-6"/></svg>),
    kill:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="m15 9-6 6m0-6 6 6m7-3c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    pause:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M9.5 15V9m5 6V9m7.5 3c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    unpause:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10Z"/><path d="M9.5 8.965c0-.477 0-.716.1-.849a.5.5 0 0 1 .364-.199c.166-.012.367.117.769.375l4.72 3.035c.349.224.523.336.583.478a.5.5 0 0 1 0 .39c-.06.142-.234.254-.583.478l-4.72 3.035c-.402.258-.603.387-.769.375a.5.5 0 0 1-.364-.2c-.1-.132-.1-.371-.1-.848v-6.07Z"/></svg>),
    remove:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M16 6v-.8c0-1.12 0-1.68-.218-2.108a2 2 0 0 0-.874-.874C14.48 2 13.92 2 12.8 2h-1.6c-1.12 0-1.68 0-2.108.218a2 2 0 0 0-.874.874C8 3.52 8 4.08 8 5.2V6m2 5.5v5m4-5v5M3 6h18m-2 0v11.2c0 1.68 0 2.52-.327 3.162a3 3 0 0 1-1.311 1.311C16.72 22 15.88 22 14.2 22H9.8c-1.68 0-2.52 0-3.162-.327a3 3 0 0 1-1.311-1.311C5 19.72 5 18.88 5 17.2V6"/></svg>),
    logs:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm0 0v6h6M8 13h8M8 17h5"/></svg>),
    terminal: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="m4 17 6-6-6-6m8 14h8"/></svg>),
    edit:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M2.876 18.116c.046-.414.069-.62.131-.814a2 2 0 0 1 .234-.485c.111-.17.259-.317.553-.61L17 3a2.828 2.828 0 1 1 4 4L7.794 20.206c-.294.294-.442.442-.611.553a2 2 0 0 1-.485.233c-.193.063-.4.086-.814.132L2.5 21.5l.376-3.384Z"/></svg>),
    plus:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 5v14m-7-7h14"/></svg>),
    check:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="m7.5 12 3 3 6-6m5.5 3c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    alert:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 9v4m0 4h.01M10.615 3.892 2.39 18.098c-.456.788-.684 1.182-.65 1.506a1 1 0 0 0 .406.705c.263.191.718.191 1.629.191h16.45c.91 0 1.365 0 1.628-.191a1 1 0 0 0 .407-.705c.034-.324-.195-.718-.65-1.506L13.383 3.892c-.454-.785-.681-1.178-.978-1.31a1 1 0 0 0-.813 0c-.296.132-.523.525-.978 1.31Z"/></svg>),
    info:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 16v-4m0-4h.01M22 12c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    users:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M22 21v-2a4.002 4.002 0 0 0-3-3.874M15.5 3.291a4.001 4.001 0 0 1 0 7.418M17 21c0-1.864 0-2.796-.305-3.53a4 4 0 0 0-2.164-2.165C13.796 15 12.864 15 11 15H8c-1.864 0-2.796 0-3.53.305a4 4 0 0 0-2.166 2.164C2 18.204 2 19.136 2 21M13.5 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z"/></svg>),
    shield:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M11.302 21.615c.221.129.332.194.488.227.122.026.298.026.42 0 .156-.034.267-.098.488-.227C14.646 20.478 20 16.908 20 12V7.217c0-.799 0-1.199-.13-1.542a2 2 0 0 0-.548-.79c-.275-.243-.65-.383-1.398-.664l-5.362-2.01c-.208-.078-.312-.117-.419-.133a1 1 0 0 0-.286 0c-.107.016-.21.055-.419.133L6.076 4.22c-.748.28-1.122.421-1.398.664a2 2 0 0 0-.547.79C4 6.018 4 6.418 4 7.217V12c0 4.908 5.354 8.478 7.302 9.615Z"/></svg>),
    bell:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M9.354 21c.705.622 1.632 1 2.646 1s1.94-.378 2.646-1M18 8A6 6 0 1 0 6 8c0 3.09-.78 5.206-1.65 6.605-.735 1.18-1.102 1.771-1.089 1.936.015.182.054.252.2.36.133.099.732.099 1.928.099H18.61c1.196 0 1.795 0 1.927-.098.147-.11.186-.179.2-.361.014-.165-.353-.755-1.088-1.936C18.78 13.206 18 11.09 18 8Z"/></svg>),
    help:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3m.08 4h.01M22 12c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    tag:      %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M8 8h.01M2 5.2v4.475c0 .489 0 .733.055.963.05.204.13.4.24.579.123.201.296.374.642.72l7.669 7.669c1.188 1.188 1.782 1.782 2.467 2.004a3 3 0 0 0 1.854 0c.685-.222 1.28-.816 2.467-2.004l2.212-2.212c1.188-1.188 1.782-1.782 2.004-2.467a3 3 0 0 0 0-1.854c-.222-.685-.816-1.28-2.004-2.467l-7.669-7.669c-.346-.346-.519-.519-.72-.642a2.001 2.001 0 0 0-.579-.24C10.409 2 10.165 2 9.676 2H5.2c-1.12 0-1.68 0-2.108.218a2 2 0 0 0-.874.874C2 3.52 2 4.08 2 5.2ZM8.5 8a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0Z"/></svg>),
    key:      %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M17 9a1.99 1.99 0 0 0-.586-1.414A1.994 1.994 0 0 0 15 7m0 8a6 6 0 1 0-5.946-5.193c.058.434.087.651.068.789a.853.853 0 0 1-.117.346c-.068.121-.187.24-.426.479l-5.11 5.11c-.173.173-.26.26-.322.36a1 1 0 0 0-.12.29C3 17.296 3 17.418 3 17.663V19.4c0 .56 0 .84.109 1.054a1 1 0 0 0 .437.437C3.76 21 4.04 21 4.6 21H7v-2h2v-2h2l1.58-1.58c.238-.238.357-.357.478-.425a.852.852 0 0 1 .346-.117c.138-.02.355.01.789.068.264.036.533.054.807.054Z"/></svg>),
  }.freeze

  def sidebar_icon(key)
    SIDEBAR_ICONS.fetch(key, "")
  end

  def action_icon(key)
    ACTION_ICONS.fetch(key, "").html_safe
  end

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
    swarm: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="currentColor" d="M17 13V6H8v16h16v-9Zm-7-5h5v5h-5Zm0 7h5v5h-5Zm12 5h-5v-5h5Z"/><path fill="currentColor" d="M28 11h-9V2h9Zm-7-2h5V4h-5Zm7 11h-2v2h2v6H4v-6h2v-2H4a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h24a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2"/><circle cx="7" cy="25" r="1" fill="currentColor"/></svg>),
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
