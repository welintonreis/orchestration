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

  def page_title(title)
    content_for(:title) { title }
    nil
  end

  def page_subtitle(subtitle)
    content_for(:page_subtitle) { subtitle }
    nil
  end

  def auto_breadcrumbs
    home = [["Home", root_path]]
    case controller_path
    when "containers"       then home + [["Docker", nil], ["Containers", containers_path]]
    when "networks"         then home + [["Docker", nil], ["Networks", networks_path]]
    when "volumes"          then home + [["Docker", nil], ["Volumes", volumes_path]]
    when "images"           then home + [["Docker", nil], ["Images", images_path]]
    when "stacks"           then home + [["Stacks", stacks_path]]
    when "swarm/dashboard"  then home + [["Swarm", swarm_path], ["Dashboard", swarm_path]]
    when "swarm/services"   then home + [["Swarm", swarm_path], ["Serviços", swarm_services_path]]
    when "swarm/policies"   then home + [["Swarm", swarm_path], ["Políticas", swarm_policies_path]]
    when "swarm/registries" then home + [["Swarm", swarm_path], ["Registries", swarm_registries_path]]
    when "environments"     then home + [["Ambientes", environments_path]]
    when "git_stacks"       then home + [["Git", nil], ["Deploy", git_stacks_path]]
    when "git_connections"  then home + [["Git", nil], ["Conexões", git_connections_path]]
    when "ambiente/tags"        then home + [["Ambiente", nil], ["Tags", ambiente_tags_path]]
    when "ambiente/licenses"    then home + [["Ambiente", nil], ["Licenças", ambiente_licenses_path]]
    when "ambiente/policies"    then home + [["Ambiente", nil], ["Políticas", ambiente_policies_path]]
    when "ambiente/registries"  then home + [["Ambiente", nil], ["Registries", ambiente_registries_path]]
    when "ambiente/groups"      then home + [["Ambiente", nil], ["Grupos", ambiente_groups_path]]
    when "roles"            then home + [["Funções", roles_path]]
    when "teams"            then home + [["Times", teams_path]]
    when "users"            then home + [["Usuários", users_path]]
    when "notifications"    then home + [["Notificações", notifications_path]]
    when "configs"          then home + [["Docker", nil], ["Configs", configs_path]]
    when "secrets"          then home + [["Docker", nil], ["Secrets", secrets_path]]
    when "settings/general"     then home + [["Configurações", nil], ["Geral", settings_general_path]]
    when "settings/auth"        then home + [["Configurações", nil], ["Autenticação", settings_auth_path]]
    when "settings/credentials" then home + [["Configurações", nil], ["Credenciais", settings_credentials_path]]
    when "settings/edge"        then home + [["Configurações", nil], ["Edge Compute", settings_edge_path]]
    when "settings/help"        then home + [["Configurações", nil], ["Ajuda", settings_help_path]]
    else []
    end
  rescue
    []
  end

  RAM_ICON_SVG = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M0 0h256v256H0z" fill="none"/><path d="M232 58H24a14 14 0 0 0-14 14v128a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0v-18h20v18a6 6 0 0 0 12 0V72a14 14 0 0 0-14-14M22 72a2 2 0 0 1 2-2h208a2 2 0 0 1 2 2v98H22Zm90 78a6 6 0 0 0 6-6V96a6 6 0 0 0-6-6H48a6 6 0 0 0-6 6v48a6 6 0 0 0 6 6Zm-58-48h52v36H54Zm90 48h64a6 6 0 0 0 6-6V96a6 6 0 0 0-6-6h-64a6 6 0 0 0-6 6v48a6 6 0 0 0 6 6m6-48h52v36h-52Z"/></svg>).freeze

  def ram_icon(css_class: "w-4 h-4")
    content_tag(:span, RAM_ICON_SVG.gsub('viewBox', %[class="#{css_class}" viewBox]).html_safe, class: "inline-flex items-center")
  end

  CPU_ICON_SVG = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M0 0h24v24H0z" fill="none"/><path d="M13.424 13.644a1.4 1.4 0 0 0 .451.299a1.5 1.5 0 0 0 .578.107a1.53 1.53 0 0 0 1.202-.53l-.513-.391a.93.93 0 0 1-.683.301a.8.8 0 0 1-.491-.138a.7.7 0 0 1-.257-.374l-.009-.026h2.12v-.249a1.4 1.4 0 0 0-.107-.546a1.4 1.4 0 0 0-.288-.446a1.3 1.3 0 0 0-.439-.299a1.5 1.5 0 0 0-.565-.107a1.4 1.4 0 0 0-.993.412a1.5 1.5 0 0 0-.301.445a1.4 1.4 0 0 0-.107.549a1.4 1.4 0 0 0 .107.547a1.4 1.4 0 0 0 .295.446m1.004-1.789a.657.657 0 0 1 .717.542h-1.434a.657.657 0 0 1 .718-.542Zm-2.571 1.918a.75.75 0 0 0 .348.195a2 2 0 0 0 .542.059h.086v-.659a2 2 0 0 1-.257-.016a.3.3 0 0 1-.166-.074a.28.28 0 0 1-.074-.162a1.6 1.6 0 0 1-.015-.262v-.945h.515v-.607h-.515v-1.053h-.711v2.609a2.4 2.4 0 0 0 .058.556a.75.75 0 0 0 .189.359m4.341-3.732h.71v3.96h-.71Zm-6.962 2.617v-.049a.83.83 0 0 1 .188-.56a.6.6 0 0 1 .451-.192a.58.58 0 0 1 .465.185a.8.8 0 0 1 .156.518v1.434h.718v-1.532a1.25 1.25 0 0 0-.295-.896a1.19 1.19 0 0 0-1.295-.215a.96.96 0 0 0-.354.288l-.04.051v-.389h-.701v2.701h.707ZM7.405 11.3h.712v2.701h-.712Zm-.021-1.206h.75v.75h-.75ZM5.99 4.781a1.82 1.82 0 0 0-.419 1.179v12.082a1.82 1.82 0 0 0 .419 1.179a1.33 1.33 0 0 0 1.011.488H17a1.33 1.33 0 0 0 1.009-.488a1.82 1.82 0 0 0 .419-1.179V5.959a1.82 1.82 0 0 0-.419-1.179A1.34 1.34 0 0 0 17 4.292H7.001a1.34 1.34 0 0 0-1.011.489m10.421.505a.94.94 0 0 1 .938.939v11.55a.94.94 0 0 1-.938.939H7.59a.94.94 0 0 1-.939-.939V6.225a.94.94 0 0 1 .939-.939ZM3.429 11.584h1.428v.833H3.429Zm1.429-5.625a2.72 2.72 0 0 1 .628-1.767a2 2 0 0 1 1.515-.733h2.32V2H3.787a.393.393 0 0 0-.358.417v6.458h1.429Zm6.785-3.958h.715v1.458h-.715Zm-1.607 0h.893v1.458h-.893Zm-6.607 11.25h1.428v1.041H3.429Zm0-3.542h1.428v1.041H3.429Zm16.785-7.708h-5.536v1.458H17a2 2 0 0 1 1.515.733a2.73 2.73 0 0 1 .628 1.767v2.916h1.428V2.418a.39.39 0 0 0-.357-.417m-1.071 9.583h1.428v.833h-1.428Zm0-1.875h1.428v1.041h-1.428Zm-13.657 10.1a2.72 2.72 0 0 1-.628-1.767v-2.916H3.429v6.457a.39.39 0 0 0 .358.417h5.534v-1.458h-2.32a2 2 0 0 1-1.515-.733m13.657-6.558h1.428v1.041h-1.428Zm-6.072-11.25h.893v1.458h-.893Zm-3.035 18.541h.893V22h-.893Zm3.035 0h.893V22h-.893Zm6.072-2.5a2.73 2.73 0 0 1-.628 1.767a2 2 0 0 1-1.515.733h-2.322V22h5.536a.39.39 0 0 0 .357-.417v-6.457h-1.428Zm-7.5 2.5h.715V22h-.715Z"/></svg>).freeze

  def cpu_icon(css_class: "w-4 h-4")
    content_tag(:span, CPU_ICON_SVG.gsub('viewBox', %[class="#{css_class}" viewBox]).html_safe, class: "inline-flex items-center")
  end

  HEARTBEAT_ICON_SVG = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" fill="currentColor"><path d="M0 0h256v256H0z" fill="none"/><path d="M72 144H32a8 8 0 0 1 0-16h35.72l13.62-20.44a8 8 0 0 1 13.32 0l25.34 38l9.34-14A8 8 0 0 1 136 128h24a8 8 0 0 1 0 16h-19.72l-13.62 20.44a8 8 0 0 1-13.32 0L88 126.42l-9.34 14A8 8 0 0 1 72 144M178 40c-20.65 0-38.73 8.88-50 23.89C116.73 48.88 98.65 40 78 40a62.07 62.07 0 0 0-62 62v2.25a8 8 0 1 0 16-.5V102a46.06 46.06 0 0 1 46-46c19.45 0 35.78 10.36 42.6 27a8 8 0 0 0 14.8 0c6.82-16.67 23.15-27 42.6-27a46.06 46.06 0 0 1 46 46c0 53.61-77.76 102.15-96 112.8c-10.83-6.31-42.63-26-66.68-52.21a8 8 0 1 0-11.8 10.82c31.17 34 72.93 56.68 74.69 57.63a8 8 0 0 0 7.58 0C136.21 228.66 240 172 240 102a62.07 62.07 0 0 0-62-62"/></svg>).freeze

  HEARTBEAT_COLORS = {
    healthy:   "text-green-400",
    unhealthy: "text-red-400",
    unknown:   "text-yellow-400",
    nil =>     "text-yellow-400"
  }.freeze

  def heartbeat_icon(status, css_class: "w-4 h-4")
    key   = status.to_s.downcase.to_sym rescue nil
    color = HEARTBEAT_COLORS[key] || HEARTBEAT_COLORS[:unknown]
    svg   = HEARTBEAT_ICON_SVG.gsub('viewBox', %[class="#{css_class} #{color}" viewBox])
    svg.html_safe
  end

  WRENCH_SVG_INNER = %(
    <path d="M0 0h56v56H0z" fill="none"/>
    <path fill="currentColor" d="M4.673 52.303c3.698 3.697 8.807 3.495 12.84-.516c4.617-4.616 9.188-13.849 15.62-20.28c4.997-4.997 10.667-.135 17.546-6.723c2.756-2.621 4.28-6.386 3.72-9.12l-8.605 2.353c-1.434.38-2.465-.538-2.913-2.084l-.65-2.264c-.448-1.546.09-2.846 1.523-3.226l8.583-2.331c-.246-.784-.986-1.86-1.905-2.801C45.256 0 36.585.6 31.588 4.818c-7.463 7.104-1.816 14.61-6.723 19.518c-5.849 5.849-15.104 10.51-19.698 15.126c-4.033 4.011-4.212 9.12-.493 12.84m2.13-2.152c-2.42-2.465-2.242-5.938.447-8.605c4.64-4.616 14.454-9.77 19.765-15.081c5.782-5.782-.314-12.997 6.745-19.518c3.563-3.294 9.681-3.54 13.804-.381L43.15 7.73c-3.272.852-4.706 3.361-3.72 6.768l.627 2.173l2.487 9.12c-3.854.56-7.843-.111-11.562 3.564c-5.827 5.826-10.914 15.708-15.552 20.37c-2.712 2.733-6.208 2.913-8.628.425m26.06-31.798l4.819-1.277c.426-.112.672-.538.56-1.009a.79.79 0 0 0-.964-.56l-4.84 1.3a.79.79 0 0 0-.56.963c.134.47.515.717.986.583m.606 2.465l4.795-1.277a.79.79 0 0 0 .56-1.009c-.111-.426-.56-.65-.963-.56l-4.84 1.322c-.426.09-.672.538-.56.941c.134.47.537.717 1.008.583m12.885-.112l4.639-1.255c-.516 1.21-1.255 2.42-2.33 3.473c-1.323 1.278-2.69 2.017-4.102 2.42l-1.254-4.57c.896.268 1.927.246 3.047-.068m-12.302 2.577l4.862-1.3c.404-.112.65-.56.56-.986a.783.783 0 0 0-.985-.538l-4.818 1.3a.813.813 0 0 0-.583.964c.09.47.538.672.964.56M8.393 48.627c1.412 1.367 3.832 1.39 5.177-.022c1.412-1.479 1.479-3.832.022-5.244c-1.456-1.389-3.832-1.456-5.244.023c-1.389 1.434-1.411 3.832.045 5.243"/>
  ).freeze

  def infra_icon(parametrized:, css_class: "w-4 h-4", title: nil)
    color = parametrized ? "text-green-500" : "text-red-500"
    slash = parametrized ? "" : %(<line x1="8" y1="8" x2="48" y2="48" stroke="currentColor" stroke-width="5" stroke-linecap="round"/>)
    title_el = title ? %(<title>#{ERB::Util.html_escape(title)}</title>) : ""
    %(<svg xmlns="http://www.w3.org/2000/svg" class="#{css_class} #{color} flex-shrink-0" viewBox="0 0 56 56">#{title_el}#{WRENCH_SVG_INNER}#{slash}</svg>).html_safe
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
    home:       %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M13.5 8.183V4.817q0-.357.234-.587t.58-.23h4.88q.347 0 .576.23t.23.587v3.366q0 .358-.234.587q-.234.23-.58.23h-4.88q-.346 0-.576-.23t-.23-.587M4 11.2V4.8q0-.34.234-.57t.58-.23h4.88q.347 0 .576.23t.23.57v6.4q0 .34-.234.57t-.58.23h-4.88q-.346 0-.576-.23T4 11.2m9.5 8v-6.4q0-.34.234-.57t.58-.23h4.88q.347 0 .576.23t.23.57v6.4q0 .34-.234.57t-.58.23h-4.88q-.346 0-.576-.23t-.23-.57M4 19.183v-3.366q0-.357.234-.587t.58-.23h4.88q.347 0 .576.23t.23.587v3.366q0 .358-.234.587q-.234.23-.58.23h-4.88q-.346 0-.576-.23T4 19.183M5 11h4.5V5H5zm9.5 8H19v-6h-4.5zm0-11H19V5h-4.5zM5 19h4.5v-3H5zm4.5-3"/></svg>),
    dashboard:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M9 8.5a1 1 0 1 1-2 0a1 1 0 0 1 2 0M6 13a1 1 0 1 0 0-2a1 1 0 0 0 0 2m12 0a1 1 0 1 0 0-2a1 1 0 0 0 0 2m-2-3.5a1 1 0 1 0 0-2a1 1 0 0 0 0 2" opacity=".5"/><path fill="currentColor" d="m15.943 10.498l-4.055 4.505A2 2 0 0 0 10 17h4a2 2 0 0 0-.603-1.431l3.66-4.067a.75.75 0 1 0-1.114-1.004M5 15.25a.75.75 0 0 0 0 1.5h1.5a.75.75 0 0 0 0-1.5zm14.75.75a.75.75 0 0 0-.75-.75h-1.5a.75.75 0 0 0 0 1.5H19a.75.75 0 0 0 .75-.75m-7-10a.75.75 0 0 0-1.5 0v1.5a.75.75 0 0 0 1.5 0z"/><path fill="currentColor" d="M12 3.25C6.063 3.25 1.25 8.063 1.25 14c0 1.498.307 2.927.862 4.224l.005.012c.215.502.363.848.817 1.332c.183.195.439.39.677.548c.238.157.519.315.77.407c.624.227 1.168.227 1.937.227h11.364c.769 0 1.313 0 1.937-.227c.252-.092.532-.25.77-.407s.494-.353.677-.548c.454-.484.603-.83.817-1.332l.005-.012c.555-1.297.862-2.726.862-4.224c0-5.937-4.813-10.75-10.75-10.75M2.75 14a9.25 9.25 0 0 1 18.5 0c0 1.292-.264 2.52-.741 3.634c-.204.477-.267.62-.536.907c-.071.075-.22.197-.41.323c-.19.125-.36.214-.458.25c-.352.128-.632.136-1.502.136H6.397c-.87 0-1.15-.008-1.502-.136a2.6 2.6 0 0 1-.458-.25a2.6 2.6 0 0 1-.41-.323c-.269-.287-.332-.43-.536-.907A9.2 9.2 0 0 1 2.75 14"/></svg>),
    stacks:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><g fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"><path d="m20.27 7.796l-3.61 1.876l-4.392 2.236a.55.55 0 0 1-.536 0L7.341 9.672L3.73 7.796a.594.594 0 0 1 0-1.06l8.014-3.925a.57.57 0 0 1 .512 0l8.014 3.925a.594.594 0 0 1 0 1.06"/><path d="m7.34 9.672l-3.61 1.723a.594.594 0 0 0 0 1.06l3.61 1.876l4.392 2.236a.55.55 0 0 0 .536 0l4.391-2.236l3.611-1.875a.594.594 0 0 0 0-1.014l-3.61-1.77"/><path d="m7.34 14.33l-3.61 1.725a.594.594 0 0 0 0 1.06l8.002 4.065a.55.55 0 0 0 .536 0l8.002-4.065a.594.594 0 0 0 0-1.014l-3.61-1.77"/></g></svg>),
    services:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="currentColor" d="m22.505 11.637l-5.989-3.5a1 1 0 0 0-1.008-.001l-6.011 3.5A1 1 0 0 0 9 12.5v7a1 1 0 0 0 .497.864l6.011 3.5A.96.96 0 0 0 16 24c.174 0 .36-.045.516-.137l5.989-3.5A1 1 0 0 0 23 19.5v-7a1 1 0 0 0-.495-.863m-6.494-1.48l4.007 2.343l-4.007 2.342l-4.023-2.342zM11 14.24l4 2.33v4.685l-4-2.33zm6 7.025v-4.683l4-2.338v4.683z"/><path fill="currentColor" d="M16 1a1 1 0 0 0-.504.136l-12 7A1 1 0 0 0 3 9v14a1 1 0 0 0 .496.864l12 7a1 1 0 0 0 1.008 0l11-6.417l-1.008-1.727L16 28.842L5 22.426V9.575l11-6.417l11 6.416V17h2V9a1 1 0 0 0-.496-.864l-12-7A1 1 0 0 0 16 1"/></svg>),
    containers: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 256 256"><path d="M0 0h256v256H0z" fill="none"/><path fill="currentColor" d="M236.4 70.65L130.2 40.31a8 8 0 0 0-3.33-.23L21.74 55.1A16.08 16.08 0 0 0 8 70.94v114.12a16.08 16.08 0 0 0 13.74 15.84l105.13 15a8.5 8.5 0 0 0 1.13.1a8 8 0 0 0 2.2-.31l106.2-30.34A16.07 16.07 0 0 0 248 170V86a16.07 16.07 0 0 0-11.6-15.35M96 120H80V62.94l40-5.72v141.56l-40-5.72V136h16a8 8 0 0 0 0-16M24 70.94l40-5.72V120H48a8 8 0 0 0 0 16h16v54.78l-40-5.72Zm112 126.45V58.61L232 86v84Z"/></svg>),
    images:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 16 16"><path d="M0 0h16v16H0z" fill="none"/><path fill="currentColor" d="M8 0C3.6 0 0 3.6 0 8s3.6 8 8 8s8-3.6 8-8s-3.6-8-8-8m7 8c0 1.1-.2 2.1-.7 3l-2.7-1.2c.2-.6.4-1.2.4-1.8c0-2.2-1.8-4-4-4c-.5 0-.9.1-1.4.3L5.4 1.5c.6-.2 1.2-.4 1.8-.5l.3 3H8V1c3.9 0 7 3.1 7 7M8 5c1.7 0 3 1.3 3 3s-1.3 3-3 3s-3-1.3-3-3s1.3-3 3-3M1 8c0-1.1.2-2.1.7-3l2.7 1.2C4.2 6.8 4 7.4 4 8c0 2.2 1.8 4 4 4c.5 0 .9-.1 1.4-.3l1.2 2.8c-.6.2-1.2.4-1.8.5l-.3-3H8v3c-3.9 0-7-3.1-7-7"/><path fill="currentColor" d="M10 8a2 2 0 1 1-3.999.001A2 2 0 0 1 10 8"/></svg>),
    networks:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 256 256"><path d="M0 0h256v256H0z" fill="none"/><path fill="currentColor" d="M232 114h-98V86h10a14 14 0 0 0 14-14V40a14 14 0 0 0-14-14h-32a14 14 0 0 0-14 14v32a14 14 0 0 0 14 14h10v28H24a6 6 0 0 0 0 12h34v36H48a14 14 0 0 0-14 14v32a14 14 0 0 0 14 14h32a14 14 0 0 0 14-14v-32a14 14 0 0 0-14-14H70v-36h116v18a6 6 0 0 0 12 0v-18h34a6 6 0 0 0 0-12M110 72V40a2 2 0 0 1 2-2h32a2 2 0 0 1 2 2v32a2 2 0 0 1-2 2h-32a2 2 0 0 1-2-2M82 176v32a2 2 0 0 1-2 2H48a2 2 0 0 1-2-2v-32a2 2 0 0 1 2-2h32a2 2 0 0 1 2 2m138.24-3.76L200.48 192l19.76 19.76a6 6 0 1 1-8.48 8.48L192 200.48l-19.76 19.76a6 6 0 0 1-8.48-8.48L183.52 192l-19.76-19.76a6 6 0 0 1 8.48-8.48L192 183.52l19.76-19.76a6 6 0 0 1 8.48 8.48"/></svg>),
    volumes:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 36 36"><path d="M0 0h36v36H0z" fill="none"/><path fill="currentColor" d="M8 17.58a32.4 32.4 0 0 0 6.3.92a4.1 4.1 0 0 1 .92-1.37a31 31 0 0 1-7.22-1Z"/><path fill="currentColor" d="M6 28V8.19c.34-.76 4.31-2.11 11-2.11s10.67 1.35 11 2v.3c-.82.79-4.58 2.05-11.11 2.05A33.5 33.5 0 0 1 8 9.44v1.44a35.6 35.6 0 0 0 8.89 1c4.29 0 8.8-.58 11.11-1.82v5.07a5.3 5.3 0 0 1-1.81.88H30V8.12c0-3.19-8.17-4-13-4s-13 .85-13 4V28c0 2.63 5.39 3.68 10 4v-2c-4.87-.34-7.72-1.38-8-2"/><path fill="currentColor" d="M8 24.28a31.3 31.3 0 0 0 6 .89v-1.4a29 29 0 0 1-6-.93Z"/><path fill="currentColor" d="M32 18H18a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V20a2 2 0 0 0-2-2M18 32V20h14v12Z"/><path fill="currentColor" d="M21 21.7a.7.7 0 0 0-.7.7v7.49a.7.7 0 0 0 1.4 0V22.4a.7.7 0 0 0-.7-.7"/><path fill="currentColor" d="M25 21.82a.7.7 0 0 0-.7.7V30a.7.7 0 1 0 1.4 0v-7.48a.7.7 0 0 0-.7-.7"/><path fill="currentColor" d="M29 21.7a.7.7 0 0 0-.7.7v7.49a.7.7 0 1 0 1.4 0V22.4a.7.7 0 0 0-.7-.7"/></svg>),
    configs:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M12 18H4v-8h16v2.078a7 7 0 0 1 2 .603V10a2 2 0 0 0-2-2l-1.488-.015l-5.302-3.43A1.96 1.96 0 0 0 14 3a2.03 2.03 0 0 0-1-1.721V0h-1v2a1 1 0 1 1-1 1h-1a1.96 1.96 0 0 0 .796 1.56L5.5 7.984L4 8a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h8.08a7 7 0 0 1-.08-1.003A7 7 0 0 1 12 18m-.005-13.026L12 5c.006 0 .01-.027.017-.027L17 8H7Z"/><path fill="currentColor" d="M15 13.26V12a1 1 0 0 0-2 0v3.408a7 7 0 0 1 2-2.148M18 11a1 1 0 0 0-1 1v.294A7 7 0 0 1 19 12a1 1 0 0 0-1-1M6 11a1 1 0 0 0-1 1v4a1 1 0 0 0 2 0v-4a1 1 0 0 0-1-1m4 0a1 1 0 0 0-1 1v4a1 1 0 0 0 2 0v-4a1 1 0 0 0-1-1m13.879 9.319l-1.07-.83a4 4 0 0 0 .04-.49a2.6 2.6 0 0 0-.04-.49l1.06-.83a.26.26 0 0 0 .06-.32l-1-1.73a.25.25 0 0 0-.31-.11l-1.239.5a3.4 3.4 0 0 0-.85-.49l-.19-1.319a.24.24 0 0 0-.24-.21h-1.998a.26.26 0 0 0-.25.21l-.19 1.32a4 4 0 0 0-.85.49l-1.239-.5a.26.26 0 0 0-.31.11l-1 1.73a.25.25 0 0 0 .06.32l1.06.829a4 4 0 0 0 0 .98l-1.06.83a.26.26 0 0 0-.06.32l1 1.73a.25.25 0 0 0 .31.11l1.24-.5a3.4 3.4 0 0 0 .849.49l.19 1.319a.25.25 0 0 0 .25.21H20.1a.26.26 0 0 0 .25-.21l.19-1.32a3.7 3.7 0 0 0 .839-.49l1.25.5a.26.26 0 0 0 .31-.11l.999-1.73a.26.26 0 0 0-.06-.32m-4.758.18a1.5 1.5 0 1 1 1.5-1.5a1.497 1.497 0 0 1-1.5 1.5"/></svg>),
    secrets:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M8 21c2.76 0 5-2.24 5-5c0-1.02-.31-1.96-.83-2.75l3.33-3.33l1.79 1.79l1.41-1.41l-1.79-1.79L18 7.42l2.29 2.29L21.7 8.3l-2.29-2.29l1.29-1.29l-1.41-1.41l-8.54 8.54c-.79-.52-1.74-.83-2.75-.83c-2.76 0-5 2.24-5 5s2.24 5 5 5Zm0-8c1.65 0 3 1.35 3 3s-1.35 3-3 3s-3-1.35-3-3s1.35-3 3-3"/></svg>),
    git:        %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="#e64a19" d="M13.172 2.828L11.78 4.22l1.91 1.91l2 2A2.986 2.986 0 0 1 20 10.81a3.25 3.25 0 0 1-.31 1.31l2.06 2a2.68 2.68 0 0 1 3.37.57a2.86 2.86 0 0 1 .88 2.117a3.02 3.02 0 0 1-.856 2.109A2.9 2.9 0 0 1 23 19.81a2.93 2.93 0 0 1-2.13-.87a2.694 2.694 0 0 1-.56-3.38l-2-2.06a3 3 0 0 1-.31.12V20a3 3 0 0 1 1.44 1.09a2.92 2.92 0 0 1 .56 1.72a2.88 2.88 0 0 1-.878 2.128a2.98 2.98 0 0 1-2.048.871a2.981 2.981 0 0 1-2.514-4.719A3 3 0 0 1 16 20v-6.38a2.96 2.96 0 0 1-1.44-1.09a2.9 2.9 0 0 1-.56-1.72a2.9 2.9 0 0 1 .31-1.31l-3.9-3.9l-7.579 7.572a4 4 0 0 0-.001 5.658l10.342 10.342a4 4 0 0 0 5.656 0l10.344-10.344a4 4 0 0 0 0-5.656L18.828 2.828a4 4 0 0 0-5.656 0"/></svg>),
    roles:      %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="currentColor" d="M19.307 3.21a2.91 2.91 0 1 0-.223 1.94a11.64 11.64 0 0 1 8.232 7.049l1.775-.698a13.58 13.58 0 0 0-9.784-8.291m-2.822 1.638a.97.97 0 1 1 0-1.939a.97.97 0 0 1 0 1.94m-4.267.805l-.717-1.774a13.58 13.58 0 0 0-8.291 9.784a2.91 2.91 0 1 0 1.94.223a11.64 11.64 0 0 1 7.068-8.233m-8.34 11.802a.97.97 0 1 1 0-1.94a.97.97 0 0 1 0 1.94m12.607 8.727a2.91 2.91 0 0 0-2.599 1.62a11.64 11.64 0 0 1-8.233-7.05l-1.774.717a13.58 13.58 0 0 0 9.813 8.291a2.91 2.91 0 1 0 2.793-3.578m0 3.879a.97.97 0 1 1 0-1.94a.97.97 0 0 1 0 1.94M32 16.485a2.91 2.91 0 1 0-4.199 2.599a11.64 11.64 0 0 1-7.05 8.232l.718 1.775a13.58 13.58 0 0 0 8.291-9.813A2.91 2.91 0 0 0 32 16.485m-2.91.97a.97.97 0 1 1 0-1.94a.97.97 0 0 1 0 1.94"/><path fill="currentColor" d="M19.19 16.35a3.879 3.879 0 1 0-5.42 0a4.85 4.85 0 0 0-2.134 4.014v1.939h9.697v-1.94a4.85 4.85 0 0 0-2.143-4.014m-4.645-2.774a1.94 1.94 0 1 1 3.88 0a1.94 1.94 0 0 1-3.88 0m-.97 6.788a2.91 2.91 0 1 1 5.819 0z"/></svg>),
    policies:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 48 48"><path d="M0 0h48v48H0z" fill="none"/><g fill="currentColor"><path d="M18 11a1 1 0 0 1 1-1h10a1 1 0 1 1 0 2H19a1 1 0 0 1-1-1m-3 5a1 1 0 1 0 0 2h18a1 1 0 1 0 0-2zm-1 5a1 1 0 0 1 1-1h18a1 1 0 1 1 0 2H15a1 1 0 0 1-1-1m1 3a1 1 0 1 0 0 2h18a1 1 0 1 0 0-2z"/><path fill-rule="evenodd" d="M38 36a4 4 0 0 1-4 4h-3v4l-3-1.5l-3 1.5v-4H14a4 4 0 0 1-4-4V8a4 4 0 0 1 4-4h20a4 4 0 0 1 4 4zM14 6a2 2 0 0 0-2 2v28a2 2 0 0 0 2 2h11v-2.354a4 4 0 1 1 6 0V38h3a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2zm15 30.874a4 4 0 0 1-2 0v3.89l1-.5l1 .5zM28 35a2 2 0 1 0 0-4a2 2 0 0 0 0 4" clip-rule="evenodd"/></g></svg>),
    tags:       %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="m21.41 11.58l-9-9A2 2 0 0 0 11 2H4a2 2 0 0 0-2 2v7a2 2 0 0 0 .59 1.42l9 9A2 2 0 0 0 13 22a2 2 0 0 0 1.41-.59l7-7A2 2 0 0 0 22 13a2 2 0 0 0-.59-1.42M13 20l-9-9V4h7l9 9M6.5 5A1.5 1.5 0 1 1 5 6.5A1.5 1.5 0 0 1 6.5 5"/></svg>),
    license:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 36 36"><path d="M0 0h36v36H0z" fill="none"/><path fill="currentColor" d="M27.46 17.23a6.36 6.36 0 0 0-4.4 11l-1.94 2.37l.9 3.61l3.66-4.46a6.26 6.26 0 0 0 3.55 0l3.66 4.46l.9-3.61l-1.94-2.37a6.36 6.36 0 0 0-4.4-11Zm0 10.68a4.31 4.31 0 1 1 4.37-4.31a4.35 4.35 0 0 1-4.37 4.31"/><path fill="currentColor" d="M30 13.5A7.5 7.5 0 0 1 22.5 6H4a2 2 0 0 0-2 2v20a2 2 0 0 0 2 2h15l.57-.7l.93-1.14A8.34 8.34 0 0 1 34 18.37v-6a7.46 7.46 0 0 1-4 1.13M17 24.6H7V23h10Zm1-7H7V16h11Zm6-4H7V12h17Z"/><circle cx="30" cy="6" r="5" fill="currentColor"/></svg>),
    sub:        '<svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3 text-gray-600" fill="currentColor" viewBox="0 0 8 8"><circle cx="4" cy="4" r="2"/></svg>',
    swarm_hex:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 512 512"><path d="M0 0h512v512H0z" fill="none"/><path fill="currentColor" d="m451.47 49.25l-70.22.125l-5.47-.03L373.064 54l-34.344 58.875l-58.876.125l-31.188-53.375l-2.625-4.72l-5.468-.06l-70.218.124l-5.5-.032l-2.688 4.656l-34 58.312l-65.562.125l-5.47-.03l-2.718 4.656l-35.093 60.188l-2.688 4.656l2.78 4.688l31.126 53.28l-33.75 57.938l-2.718 4.656l2.782 4.688l35.125 60.094l2.593 4.75l5.5.03l67.812-.124l31.03 53.03l2.595 4.75l5.5.033l67.594-.125l31.187 53.375l2.626 4.718l5.47.064l70.218-.125l5.312.092l2.72-4.656l34.155-58.375l65.564-.124l5.312.094l2.688-4.656l35.28-60.25l2.688-4.656l-2.78-4.688l-35.126-60.094l-2.594-4.72l-5.5-.06l-67.593.124l-27.19-46.5l32.94-56.344l61.53-.125l5.313.095l2.687-4.656l35.25-60.25l2.72-4.657l-2.783-4.688l-35.125-60.094l-2.593-4.718l-5.5-.062zm-5.345 18.656l29.5 51.094l-29.53 50.688l-59.47.093L357 118.876l29.656-50.906zM127.47 136.562l29.5 51.094l-29.532 50.688l-59.47.094l-29.624-50.907L68 136.626l59.47-.063zm106.905 58l28.53 49.5l-30.374 52.125l-57.78.094l-29.5-50.717l29.656-50.907l59.47-.094zm105.313 57.344l29.375 50.938l-29.532 50.72l-59.467.06l-28.72-49.343L281.907 252zm106.78 57.875l29.5 51.095l-29.53 50.688l-59.47.062l-29.624-50.875L387 309.844l59.47-.063zm-214.53 5.19l29.406 50.967l-29.53 50.688l-59.47.063l-29.625-50.907l29.56-50.717l59.657-.094z"/></svg>),
    registry:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 16 16"><path d="M0 0h16v16H0z" fill="none"/><path fill="currentColor" fill-rule="evenodd" d="m8 2.732l-2.945 1.7L8 6.135l2.945-1.701zm4.445.834L8 1L3.555 3.566l-1.43-.825a.75.75 0 1 0-.75 1.298l1.429.826V10l4.446 2.567v1.683a.75.75 0 0 0 1.5 0v-1.683L13.196 10V4.865l1.43-.826a.75.75 0 0 0-.751-1.298zm-.749 2.165L8.75 7.433v3.402l2.946-1.701zM4.304 9.134l2.946 1.7v-3.4L4.304 5.73z" clip-rule="evenodd"/></svg>),
    nodes:      %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 36 36"><path d="M0 0h36v36H0z" fill="none"/><path fill="currentColor" d="M10.5 34.29L2 29.39v-9.81l8.5-4.9l8.5 4.9v9.81ZM4 28.23L10.5 32l6.5-3.77v-7.49L10.5 17L4 20.74Z" class="clr-i-outline clr-i-outline-path-1"/><path fill="currentColor" d="m25.5 34.29l-8.5-4.9v-9.81l8.5-4.9l8.5 4.9v9.81ZM19 28.23L25.5 32l6.5-3.77v-7.49L25.5 17L19 20.74Z" class="clr-i-outline clr-i-outline-path-2"/><path fill="currentColor" d="m18 21.32l-8.5-4.9V6.61l8.5-4.9l8.5 4.9v9.81Zm-6.5-6.06L18 19l6.5-3.75V7.77L18 4l-6.5 3.77Z" class="clr-i-outline clr-i-outline-path-3"/><path fill="none" d="M0 0h36v36H0z"/></svg>),
    details:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M4.25 4A2.25 2.25 0 0 0 2 6.25v2.5A2.25 2.25 0 0 0 4.25 11h2.5A2.25 2.25 0 0 0 9 8.75v-2.5A2.25 2.25 0 0 0 6.75 4zM3.5 6.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 .75.75v2.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1-.75-.75zM11.25 5a.75.75 0 0 0 0 1.5h10a.75.75 0 0 0 0-1.5zm0 3a.75.75 0 0 0 0 1.5h7a.75.75 0 0 0 0-1.5zm-7 5A2.25 2.25 0 0 0 2 15.25v2.5A2.25 2.25 0 0 0 4.25 20h2.5A2.25 2.25 0 0 0 9 17.75v-2.5A2.25 2.25 0 0 0 6.75 13zm-.75 2.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 .75.75v2.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1-.75-.75zM11.25 14a.75.75 0 0 0 0 1.5h10a.75.75 0 0 0 0-1.5zm0 3a.75.75 0 0 0 0 1.5h7a.75.75 0 0 0 0-1.5z"/></svg>),
    user:       %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><g fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="6" r="4"/><path d="M20 17.5c0 2.485 0 4.5-8 4.5s-8-2.015-8-4.5S7.582 13 12 13s8 2.015 8 4.5Z"/></g></svg>),
    user_group: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M12 5.5A3.5 3.5 0 0 1 15.5 9a3.5 3.5 0 0 1-3.5 3.5A3.5 3.5 0 0 1 8.5 9A3.5 3.5 0 0 1 12 5.5M5 8c.56 0 1.08.15 1.53.42c-.15 1.43.27 2.85 1.13 3.96C7.16 13.34 6.16 14 5 14a3 3 0 0 1-3-3a3 3 0 0 1 3-3m14 0a3 3 0 0 1 3 3a3 3 0 0 1-3 3c-1.16 0-2.16-.66-2.66-1.62a5.54 5.54 0 0 0 1.13-3.96c.45-.27.97-.42 1.53-.42M5.5 18.25c0-2.07 2.91-3.75 6.5-3.75s6.5 1.68 6.5 3.75V20h-13zM0 20v-1.5c0-1.39 1.89-2.56 4.45-2.9c-.59.68-.95 1.62-.95 2.65V20zm24 0h-3.5v-1.75c0-1.03-.36-1.97-.95-2.65c2.56.34 4.45 1.51 4.45 2.9z"/></svg>),
    org_group:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="currentColor" d="M28 10h-5V6a2 2 0 0 0-2-2H11a2 2 0 0 0-2 2v4H4a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h24a2 2 0 0 0 2-2V12a2 2 0 0 0-2-2M4 28V12h5v2H7v2h2v2H7v2h2v2H7v2h2v4Zm17 0H11V6h10Zm7 0h-5v-4h2v-2h-2v-2h2v-2h-2v-2h2v-2h-2v-2h5Z"/><path fill="currentColor" d="M14 8h4v2h-4zm0 4h4v2h-4zm0 4h4v2h-4z"/></svg>),
    log_lines:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 12h.01M4 6h.01M4 18h.01M8 18h2m-2-6h2M8 6h2m4 0h6m-6 6h6m-6 6h6"/></svg>),
    alert_tri:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-miterlimit="10" stroke-width="1.5" d="M12 16h.008M12 10v3m-1.425-7.783L3.517 17a1.667 1.667 0 0 0 1.425 2.5h14.116a1.666 1.666 0 0 0 1.425-2.5L13.426 5.217a1.666 1.666 0 0 0-2.85 0"/></svg>),
    notif_bell: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M6.429 2.413a.75.75 0 0 0-1.13-.986l-1.292 1.48a4.75 4.75 0 0 0-1.17 3.024L2.78 8.65a.75.75 0 1 0 1.5.031l.056-2.718a3.25 3.25 0 0 1 .801-2.069z"/><path fill="currentColor" fill-rule="evenodd" d="M6.237 7.7a4.214 4.214 0 0 1 4.206-3.95H11V3a1 1 0 1 1 2 0v.75h.557a4.214 4.214 0 0 1 4.206 3.95l.221 3.534a7.4 7.4 0 0 0 1.308 3.754a1.617 1.617 0 0 1-1.135 2.529l-3.407.408V19a2.75 2.75 0 1 1-5.5 0v-1.075l-3.407-.409a1.617 1.617 0 0 1-1.135-2.528a7.4 7.4 0 0 0 1.308-3.754zm4.206-2.45a2.714 2.714 0 0 0-2.709 2.544l-.22 3.534a8.9 8.9 0 0 1-1.574 4.516a.117.117 0 0 0 .082.183l3.737.449c1.489.178 2.993.178 4.482 0l3.737-.449a.117.117 0 0 0 .082-.183a8.9 8.9 0 0 1-1.573-4.516l-.221-3.534a2.714 2.714 0 0 0-2.709-2.544zm1.557 15c-.69 0-1.25-.56-1.25-1.25v-.75h2.5V19c0 .69-.56 1.25-1.25 1.25" clip-rule="evenodd"/><path fill="currentColor" d="M17.643 1.355a.75.75 0 0 0-.072 1.058l1.292 1.48a3.25 3.25 0 0 1 .8 2.07l.057 2.717a.75.75 0 0 0 1.5-.031l-.057-2.718a4.75 4.75 0 0 0-1.17-3.024l-1.292-1.48a.75.75 0 0 0-1.058-.072"/></svg>),
    auth_shield: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 48 48"><path d="M0 0h48v48H0z" fill="none"/><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" d="M24 43.5c12.764-5.885 14.86-15.67 14.86-21.982V16.91S33.43 14.286 24 14.286S9.14 16.909 9.14 16.909v4.61c0 6.31 2.096 16.096 14.86 21.981"/><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" d="M32.013 14.96v-2.447a8.013 8.013 0 0 0-16.026 0v2.448m9.837 12.109a3.79 3.79 0 1 0-3.648 0a5.67 5.67 0 0 0-3.849 5.368h11.346a5.67 5.67 0 0 0-3.849-5.367"/></svg>),
    credentials: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" fill-rule="evenodd" d="M2 7a3 3 0 0 1 3-3h14a3 3 0 0 1 3 3v1H2zm0 3v7a3 3 0 0 0 3 3h14a3 3 0 0 0 3-3v-7zm5 2a1 1 0 1 0 0 2h5a1 1 0 1 0 0-2z" clip-rule="evenodd"/></svg>),
    edge:        %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 32 32"><path d="M0 0h32v32H0z" fill="none"/><path fill="currentColor" d="M22 6h4v4h-4z"/><circle cx="7" cy="7" r="1" fill="currentColor"/><circle cx="25" cy="25" r="1" fill="currentColor"/><circle cx="25" cy="21" r="1" fill="currentColor"/><circle cx="25" cy="17" r="1" fill="currentColor"/><path fill="currentColor" d="M22 17v-2h-2v-1a2 2 0 0 0-2-2h-1v-2h-2v2h-2v-2h-2v2h-1a2 2 0 0 0-2 2v1H6v2h2v2H6v2h2v1a2 2 0 0 0 2 2h1v2h2v-2h2v2h2v-2h1a2 2 0 0 0 2-2v-1h2v-2h-2v-2Zm-4 5h-8v-8h8Z"/><path fill="currentColor" d="M28 30H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h24a2 2 0 0 1 2 2v24a2 2 0 0 1-2 2M4 4v24h24V4Z"/></svg>),
    chat_help:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24"><path d="M0 0h24v24H0z" fill="none"/><path fill="currentColor" d="M9 20H5q-.825 0-1.412-.587T3 18V4q0-.825.588-1.412T5 2h14q.825 0 1.413.588T21 4v14q0 .825-.587 1.413T19 20h-4l-2.3 2.3q-.3.3-.7.3t-.7-.3zm-4-2h4.8l2.2 2.2l2.2-2.2H19V4H5zm6.9-1q.525 0 .888-.363t.362-.887t-.363-.888t-.887-.362t-.888.363t-.362.887t.363.888t.887.362m1.75-9q0 .425-.275.913t-.925 1.062q-.425.375-.687.713t-.438.687q-.1.2-.15.4t-.1.45q-.05.375.2.65t.65.275q.35 0 .625-.25t.375-.675q.075-.35.288-.65t.687-.775q.875-.875 1.238-1.475T15.5 8q0-1.35-.912-2.175T12.1 5q-1.125 0-1.95.475T8.825 6.8q-.175.3-.012.625t.512.45q.325.125.65 0t.525-.4q.275-.35.675-.562T12.1 6.7q.65 0 1.1.362t.45.938"/></svg>),
  }.freeze

  # Untitled UI action icons (used in table rows, buttons, etc.)
  ACTION_ICONS = {
    play:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M5 4.99c0-.972 0-1.457.202-1.725a1 1 0 0 1 .738-.395c.335-.02.74.25 1.548.788l10.515 7.01c.668.446 1.002.668 1.118.949a1 1 0 0 1 0 .766c-.116.28-.45.503-1.118.948l-10.515 7.01c-.809.54-1.213.809-1.548.789a1 1 0 0 1-.738-.395C5 20.467 5 19.98 5 19.01V4.99Z"/></svg>),
    stop:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M6 5h12a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z"/></svg>),
    restart:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M21 10s-2.005-2.732-3.634-4.362a9 9 0 1 0 2.282 8.862M21 10V4m0 6h-6"/></svg>),
    kill:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="m15 9-6 6m0-6 6 6m7-3c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    pause:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M9.5 15V9m5 6V9m7.5 3c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    unpause:  %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10Z"/><path d="M9.5 8.965c0-.477 0-.716.1-.849a.5.5 0 0 1 .364-.199c.166-.012.367.117.769.375l4.72 3.035c.349.224.523.336.583.478a.5.5 0 0 1 0 .39c-.06.142-.234.254-.583.478l-4.72 3.035c-.402.258-.603.387-.769.375a.5.5 0 0 1-.364-.2c-.1-.132-.1-.371-.1-.848v-6.07Z"/></svg>),
    remove:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M16 6v-.8c0-1.12 0-1.68-.218-2.108a2 2 0 0 0-.874-.874C14.48 2 13.92 2 12.8 2h-1.6c-1.12 0-1.68 0-2.108.218a2 2 0 0 0-.874.874C8 3.52 8 4.08 8 5.2V6m2 5.5v5m4-5v5M3 6h18m-2 0v11.2c0 1.68 0 2.52-.327 3.162a3 3 0 0 1-1.311 1.311C16.72 22 15.88 22 14.2 22H9.8c-1.68 0-2.52 0-3.162-.327a3 3 0 0 1-1.311-1.311C5 19.72 5 18.88 5 17.2V6"/></svg>),
    logs:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm0 0v6h6M8 13h8M8 17h5"/></svg>),
    terminal: %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="m4 17 6-6-6-6m8 14h8"/></svg>),
    edit:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M2.876 18.116c.046-.414.069-.62.131-.814a2 2 0 0 1 .234-.485c.111-.17.259-.317.553-.61L17 3a2.828 2.828 0 1 1 4 4L7.794 20.206c-.294.294-.442.442-.611.553a2 2 0 0 1-.485.233c-.193.063-.4.086-.814.132L2.5 21.5l.376-3.384Z"/></svg>),
    plus:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 5v14m-7-7h14"/></svg>),
    check:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="m7.5 12 3 3 6-6m5.5 3c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    alert:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 9v4m0 4h.01M10.615 3.892 2.39 18.098c-.456.788-.684 1.182-.65 1.506a1 1 0 0 0 .406.705c.263.191.718.191 1.629.191h16.45c.91 0 1.365 0 1.628-.191a1 1 0 0 0 .407-.705c.034-.324-.195-.718-.65-1.506L13.383 3.892c-.454-.785-.681-1.178-.978-1.31a1 1 0 0 0-.813 0c-.296.132-.523.525-.978 1.31Z"/></svg>),
    info:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M12 16v-4m0-4h.01M22 12c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    users:    %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M22 21v-2a4.002 4.002 0 0 0-3-3.874M15.5 3.291a4.001 4.001 0 0 1 0 7.418M17 21c0-1.864 0-2.796-.305-3.53a4 4 0 0 0-2.164-2.165C13.796 15 12.864 15 11 15H8c-1.864 0-2.796 0-3.53.305a4 4 0 0 0-2.166 2.164C2 18.204 2 19.136 2 21M13.5 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z"/></svg>),
    shield:   %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M11.302 21.615c.221.129.332.194.488.227.122.026.298.026.42 0 .156-.034.267-.098.488-.227C14.646 20.478 20 16.908 20 12V7.217c0-.799 0-1.199-.13-1.542a2 2 0 0 0-.548-.79c-.275-.243-.65-.383-1.398-.664l-5.362-2.01c-.208-.078-.312-.117-.419-.133a1 1 0 0 0-.286 0c-.107.016-.21.055-.419.133L6.076 4.22c-.748.28-1.122.421-1.398.664a2 2 0 0 0-.547.79C4 6.018 4 6.418 4 7.217V12c0 4.908 5.354 8.478 7.302 9.615Z"/></svg>),
    bell:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M9.354 21c.705.622 1.632 1 2.646 1s1.94-.378 2.646-1M18 8A6 6 0 1 0 6 8c0 3.09-.78 5.206-1.65 6.605-.735 1.18-1.102 1.771-1.089 1.936.015.182.054.252.2.36.133.099.732.099 1.928.099H18.61c1.196 0 1.795 0 1.927-.098.147-.11.186-.179.2-.361.014-.165-.353-.755-1.088-1.936C18.78 13.206 18 11.09 18 8Z"/></svg>),
    help:     %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3m.08 4h.01M22 12c0 5.523-4.477 10-10 10S2 17.523 2 12 6.477 2 12 2s10 4.477 10 10Z"/></svg>),
    tag:      %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M8 8h.01M2 5.2v4.475c0 .489 0 .733.055.963.05.204.13.4.24.579.123.201.296.374.642.72l7.669 7.669c1.188 1.188 1.782 1.782 2.467 2.004a3 3 0 0 0 1.854 0c.685-.222 1.28-.816 2.467-2.004l2.212-2.212c1.188-1.188 1.782-1.782 2.004-2.467a3 3 0 0 0 0-1.854c-.222-.685-.816-1.28-2.004-2.467l-7.669-7.669c-.346-.346-.519-.519-.72-.642a2.001 2.001 0 0 0-.579-.24C10.409 2 10.165 2 9.676 2H5.2c-1.12 0-1.68 0-2.108.218a2 2 0 0 0-.874.874C2 3.52 2 4.08 2 5.2ZM8.5 8a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0Z"/></svg>),
    key:      %(<svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" viewBox="0 0 24 24" #{UUI_SVG_ATTRS}><path d="M17 9a1.99 1.99 0 0 0-.586-1.414A1.994 1.994 0 0 0 15 7m0 8a6 6 0 1 0-5.946-5.193c.058.434.087.651.068.789a.853.853 0 0 1-.117.346c-.068.121-.187.24-.426.479l-5.11 5.11c-.173.173-.26.26-.322.36a1 1 0 0 0-.12.29C3 17.296 3 17.418 3 17.663V19.4c0 .56 0 .84.109 1.054a1 1 0 0 0 .437.437C3.76 21 4.04 21 4.6 21H7v-2h2v-2h2l1.58-1.58c.238-.238.357-.357.478-.425a.852.852 0 0 1 .346-.117c.138-.02.355.01.789.068.264.036.533.054.807.054Z"/></svg>),
  }.freeze

  public

  # action_icon/sidebar_icon are called with an explicit receiver
  # (helpers.action_icon) from ViewComponent components, which Ruby
  # disallows for private methods — public from here on.
  def sidebar_icon(key, css_class: nil)
    svg = SIDEBAR_ICONS.fetch(key, "")
    svg = svg.gsub(/class="w-\S+ h-\S+"/, %{class="#{css_class}"}) if css_class
    svg.html_safe
  end

  def action_icon(key, css_class: nil)
    svg = ACTION_ICONS.fetch(key, "")
    svg = svg.gsub(/class="w-\S+ h-\S+"/, %{class="#{css_class}"}) if css_class
    svg.html_safe
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
      <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5 flex-shrink-0" viewBox="0 0 2048 2048">
        <path fill="currentColor" d="M768 384h512v128H768zm0 768h512v128H768zm0 256h512v128H768zm1170 640H110l160-640h242V256q0-26 10-49t27-41t41-28t50-10h768q26 0 49 10t41 27t28 41t10 50v1152h242zM640 1664h768V256H640zm1134 256l-96-384h-142v256H512v-256H370l-96 384z"/>
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
