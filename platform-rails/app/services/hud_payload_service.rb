require "pg"
require "net/http"
require "json"

# HudPayloadService — as células do Notch (HUD) de desktop (redhusky-hud).
#
# Contrato: 00_docs/hud-contract.md do repo redhusky-hud. Três células, uma por
# assunto, cada uma com as suas janelas no hover card:
#
#   Resources  UPTIME · CPU · RAM · DISCO · SWAP
#   Docker     STACKS · SERVICES · IMAGES · CONTAINERS · VOLUMES · NETWORKS
#   Databases  MASTER · REPLICAS · ANALYTICS · RABBIT · BACKUPS · DELTAS
#
# **Todo item tem um % que significa alguma coisa.** Contador puro ("48 imagens")
# não diz se está bem ou mal; o que diz é a fração contra um denominador real —
# uso contra limite, no ar contra desejado, em uso contra total, idade contra
# RPO. Onde não havia denominador honesto, ele foi buscado onde o próprio
# sistema já o define (max_connections, watermark do RabbitMQ, thresholds de
# alerta do MetricsJob), nunca inventado.
#
# `progress` é a barra (a fração natural do item, seja "cheio = bom" ou
# "cheio = ruim") e `severity` é a COR (0 = saudável, 1 = crítico). São campos
# separados de propósito: 100% de réplicas no ar é verde cheio, 92% de disco é
# vermelho cheio — mesmo número, sentidos opostos, e quem sabe a diferença é o
# servidor.
#
# Custo: o poll é de 15s e estas sondas falam com Docker, Postgres e RabbitMQ.
# O cache vive no controller (Internal::HudController); aqui cada célula é
# independente e uma que falhe é OMITIDA, nunca zerada — zerar faria "fila
# vazia" e "coletor quebrado" parecerem a mesma coisa.
class HudPayloadService
  PROC_PATH = ENV.fetch("PROC_PATH", "/proc")

  # Janela de reboot: acima disso o kernel provavelmente está desatualizado.
  # Não é incidente — é lembrete, por isso a severidade para no amarelo.
  UPTIME_WINDOW = 30.days.to_i

  # Réplicas que o cluster deve ter (master → postgres-read). Constante e não
  # "o que estiver conectado agora": o objetivo é justamente notar quando uma
  # some.
  EXPECTED_REPLICAS = 1

  # RPO: se o último backup tem mais que isto, a barra enche e fica vermelha.
  BACKUP_RPO = 24.hours.to_i

  # Corrente de deltas antes de um full novo. Restore percorre a corrente
  # inteira: quanto mais longa, mais demorado voltar.
  DELTA_CHAIN_MAX = 6

  PG_HOSTS = { master: "postgres-master", analytics: "postgres-analytics" }.freeze
  RABBIT_HOST = "rabbitmq"
  RABBIT_PORT = 15672

  def self.call = new.call

  def call
    [ resources_cell, docker_cell, databases_cell ].compact
  end

  private

  # ── Resources ────────────────────────────────────────────────────────────
  # Os limiares são os MESMOS que já disparam alerta no MetricsJob. Uma régua
  # só: o que acende o Notch é o que gera o alerta, senão a pill vira uma
  # segunda opinião sobre a mesma máquina.
  def resources_cell
    m = HostMetric.latest
    return nil unless m

    wins = [
      uptime_window,
      gauge("CPU",   m.cpu_percent,  MetricsJob::CPU_THRESHOLD,  "de 100% de uso"),
      gauge("RAM",   m.ram_percent,  MetricsJob::RAM_THRESHOLD,  "da memória do host"),
      gauge("Disco", m.disk_percent, MetricsJob::DISK_THRESHOLD, "da partição raiz"),
      gauge("Swap",  m.swap_percent, MetricsJob::SWAP_THRESHOLD, "da swap")
    ]
    # O anel mostra o recurso mais apertado — é ele que estoura primeiro.
    worst = wins.drop(1).max_by { |w| w[:severity] }

    cell("resources", "cpu", "Recursos", progress: worst[:progress], severity: worst[:severity],
                                          windows: wins)
  rescue => e
    log(:resources, e)
    nil
  end

  def uptime_window
    secs = File.read("#{PROC_PATH}/uptime").split.first.to_f.to_i
    frac = [ secs.to_f / UPTIME_WINDOW, 1.0 ].min
    { label: "Uptime", value: humanize_secs(secs), progress: frac,
      # Passou da janela de 30 dias: amarelo, não vermelho. Uptime alto não é
      # incidente, é kernel velho.
      severity: secs > UPTIME_WINDOW ? 0.5 : 0.0,
      caption: secs > UPTIME_WINDOW ? "além da janela de reboot (30d)" : "de 30d de janela de reboot" }
  end

  def gauge(label, percent, threshold, caption)
    pct = percent.to_f
    { label: label, value: "#{pct.round}%", progress: [ pct / 100.0, 1.0 ].min,
      severity: frac(pct, threshold), caption: "#{caption} · alerta em #{threshold.round}%" }
  end

  # ── Docker ───────────────────────────────────────────────────────────────
  def docker_cell
    client   = DockerClient.new
    services = client.services
    conts    = client.containers(all: true)
    df       = client.system_df || {}
    nets     = client.networks

    desired = services.sum { |s| s.dig("ServiceStatus", "DesiredTasks").to_i }
    running = services.sum { |s| s.dig("ServiceStatus", "RunningTasks").to_i }

    wins = [
      stacks_window(services),
      { label: "Services", value: "#{running}/#{desired}", progress: ratio(running, desired),
        severity: frac(desired - running, [ desired, 1 ].max),
        caption: desired == running ? "todas as tarefas convergidas" : "#{desired - running} tarefa(s) faltando" },
      images_window(df),
      containers_window(conts),
      volumes_window(df),
      networks_window(nets, conts, services)
    ]

    cell("docker", "server", "Docker",
         progress: ratio(running, desired),
         # A cor do anel é convergência: lixo acumulado não é incidente.
         severity: frac(desired - running, [ desired, 1 ].max),
         windows: wins)
  rescue => e
    log(:docker, e)
    nil
  end

  def stacks_window(services)
    stacks = services.group_by { |s| s.dig("Spec", "Labels", "com.docker.stack.namespace") }.except(nil)
    # Serviço escalado para 0 está desligado de propósito — não conta como
    # stack doente, senão toda stack pausada apareceria como incêndio.
    healthy = stacks.count do |_ns, svcs|
      svcs.all? { |s| s.dig("ServiceStatus", "RunningTasks").to_i >= s.dig("ServiceStatus", "DesiredTasks").to_i }
    end
    { label: "Stacks", value: "#{healthy}/#{stacks.size}", progress: ratio(healthy, stacks.size),
      severity: frac(stacks.size - healthy, [ stacks.size, 1 ].max),
      caption: healthy == stacks.size ? "todas de pé" : "#{stacks.size - healthy} com serviço faltando" }
  end

  def images_window(df)
    imgs  = Array(df["Images"])
    ociosas = imgs.count { |i| i["Containers"].to_i <= 0 }
    # % de lixo: imagem sem container é espaço que só espera um prune. Enche a
    # barra quando o disco está sendo desperdiçado, mas nunca passa de amarelo.
    { label: "Images", value: "#{imgs.size}", progress: ratio(ociosas, imgs.size),
      severity: [ ratio(ociosas, imgs.size) * 0.6, 0.6 ].min,
      caption: "#{ociosas} sem container · #{bytes(imgs.sum { |i| i["Size"].to_i })} no total" }
  end

  def containers_window(conts)
    rodando = conts.count { |c| c["State"] == "running" }
    { label: "Containers", value: "#{rodando}/#{conts.size}", progress: ratio(rodando, conts.size),
      severity: frac(conts.size - rodando, [ conts.size, 1 ].max) * 0.6,
      caption: "#{conts.size - rodando} parado(s)" }
  end

  def volumes_window(df)
    vols = Array(df["Volumes"])
    usados = vols.count { |v| v.dig("UsageData", "RefCount").to_i.positive? }
    { label: "Volumes", value: "#{usados}/#{vols.size}", progress: ratio(usados, vols.size),
      severity: [ ratio(vols.size - usados, vols.size) * 0.6, 0.6 ].min,
      caption: "#{vols.size - usados} órfão(s) · #{bytes(vols.sum { |v| v.dig("UsageData", "Size").to_i })}" }
  end

  # Rede "em uso" não sai da listagem: /networks só devolve Containers no
  # inspect de cada uma. Sai do que já está em mãos — o que containers e
  # serviços referenciam.
  def networks_window(nets, conts, services)
    used = Set.new
    conts.each { |c| (c.dig("NetworkSettings", "Networks") || {}).each { |name, n| used << name; used << n["NetworkID"] } }
    services.each { |s| Array(s.dig("Spec", "TaskTemplate", "Networks")).each { |n| used << n["Target"] } }
    # bridge/host/none são do próprio Docker: nunca são órfãs.
    builtin = %w[bridge host none]
    em_uso = nets.count { |n| builtin.include?(n["Name"]) || used.include?(n["Id"]) || used.include?(n["Name"]) }
    { label: "Networks", value: "#{em_uso}/#{nets.size}", progress: ratio(em_uso, nets.size),
      severity: [ ratio(nets.size - em_uso, nets.size) * 0.6, 0.6 ].min,
      caption: "#{nets.size - em_uso} sem ninguém dentro" }
  end

  # ── Databases ────────────────────────────────────────────────────────────
  def databases_cell
    wins = [
      pg_connections_window("Master", :master),
      replicas_window,
      pg_connections_window("Analytics", :analytics),
      rabbit_window,
      backups_window,
      deltas_window
    ].compact
    return nil if wins.empty?

    worst = wins.max_by { |w| w[:severity] }
    cell("databases", "database", "Bancos", progress: worst[:progress], severity: worst[:severity],
                                             windows: wins)
  rescue => e
    log(:databases, e)
    nil
  end

  # Conexões usadas sobre max_connections: é o teto que o próprio Postgres
  # define, e estourá-lo derruba aplicação — o denominador mais honesto que
  # existe para "como está o banco agora".
  def pg_connections_window(label, host_key)
    conn = pg_connect(PG_HOSTS.fetch(host_key))
    return nil unless conn

    used, max = conn.exec("select (select count(*) from pg_stat_activity), current_setting('max_connections')::int")
                    .values.first.map(&:to_i)
    { label: label, value: "#{used}/#{max}", progress: ratio(used, max),
      severity: frac(used, max * 0.9), caption: "conexões · alerta em 90% do teto" }
  rescue => e
    log(:"pg_#{host_key}", e)
    nil
  ensure
    conn&.close
  end

  def replicas_window
    conn = pg_connect(PG_HOSTS[:master])
    return nil unless conn

    streaming, total, lag = conn.exec(<<~SQL).values.first
      select count(*) filter (where state = 'streaming'), count(*),
             coalesce(round(max(extract(epoch from replay_lag))::numeric, 1), 0)
      from pg_stat_replication
    SQL
    streaming = streaming.to_i
    { label: "Replicas", value: "#{streaming}/#{EXPECTED_REPLICAS}",
      progress: ratio(streaming, EXPECTED_REPLICAS),
      severity: frac(EXPECTED_REPLICAS - streaming, EXPECTED_REPLICAS),
      caption: streaming.positive? ? "streaming · atraso #{lag.to_f.round(1)}s" : "nenhuma réplica conectada (#{total.to_i} sessão(ões))" }
  rescue => e
    log(:replicas, e)
    nil
  ensure
    conn&.close
  end

  # Memória do broker sobre o watermark: é o ponto em que o RabbitMQ BLOQUEIA
  # publishers. Não é um limite inventado por nós, é o que ele mesmo usa.
  def rabbit_window
    node = rabbit_get("/api/nodes")&.first
    return nil unless node

    over = rabbit_get("/api/overview") || {}
    mem, limit = node["mem_used"].to_i, node["mem_limit"].to_i
    msgs = over.dig("queue_totals", "messages").to_i
    { label: "Rabbit", value: "#{bytes(mem)}/#{bytes(limit)}", progress: ratio(mem, limit),
      severity: node["running"] ? frac(mem, limit * 0.8) : 1.0,
      caption: node["running"] ? "#{msgs} mensagem(ns) · #{over.dig("object_totals", "queues").to_i} filas" : "nó fora do ar" }
  rescue => e
    log(:rabbit, e)
    nil
  end

  # Idade do último backup sobre o RPO: 100% da barra = o RPO inteiro
  # consumido, e daí em diante é vermelho — que é exatamente a pergunta
  # "posso restaurar o dia de ontem?".
  def backups_window
    snap = BackupSnapshot.where(server: "master").order(captured_at: :desc).first
    return nil unless snap

    return { label: "Backups", value: "erro", progress: 1.0, severity: 1.0,
             caption: snap.error.to_s.truncate(60) } if snap.error.present?
    return { label: "Backups", value: "nenhum", progress: 1.0, severity: 1.0,
             caption: "wal-g não listou backup nenhum" } unless snap.last_backup_at

    idade = (Time.current - snap.last_backup_at).to_i
    { label: "Backups", value: "há #{humanize_secs(idade)}", progress: [ idade.to_f / BACKUP_RPO, 1.0 ].min,
      severity: frac(idade, BACKUP_RPO),
      caption: "#{snap.last_backup_type} · RPO de 24h · lido #{humanize_secs((Time.current - snap.captured_at).to_i)} atrás" }
  rescue => e
    log(:backups, e)
    nil
  end

  def deltas_window
    snap = BackupSnapshot.where(server: "master").where.not(deltas_since_full: nil).order(captured_at: :desc).first
    return nil unless snap

    n = snap.deltas_since_full.to_i
    { label: "Deltas", value: "#{n}/#{DELTA_CHAIN_MAX}", progress: [ n.to_f / DELTA_CHAIN_MAX, 1.0 ].min,
      severity: frac(n, DELTA_CHAIN_MAX),
      caption: "desde o último full · restore percorre a corrente inteira" }
  rescue => e
    log(:deltas, e)
    nil
  end

  # ── utilidades ───────────────────────────────────────────────────────────

  def cell(id, icon, label, progress:, severity:, windows:)
    { id: id, icon: icon, label: label,
      progress: round2(progress), severity: round2(severity),
      windows: windows.compact.map { |w| w.merge(progress: round2(w[:progress]), severity: round2(w[:severity])) } }
  end

  def ratio(part, total) = total.to_f.positive? ? [ part.to_f / total, 1.0 ].min : 0.0
  def frac(value, limit) = limit.to_f.positive? ? [ [ value.to_f / limit, 1.0 ].min, 0.0 ].max : 0.0
  def round2(f) = f.nil? ? nil : f.to_f.round(2)

  def pg_connect(host)
    PG.connect(host: host, port: 5432, dbname: "postgres", user: pg_user, password: pg_password,
               connect_timeout: 3)
  rescue => e
    log(:"pg_connect_#{host}", e)
    nil
  end

  def pg_user     = @pg_user     ||= File.read("/run/secrets/pg_user").strip
  def pg_password = @pg_password ||= File.read("/run/secrets/pg_password").strip

  def rabbit_get(path)
    uri = URI("http://#{RABBIT_HOST}:#{RABBIT_PORT}#{path}")
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(ENV.fetch("RABBITMQ_USER", "welintonreis"), ENV["RABBITMQ_PASSWORD"].to_s)
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 4) { |http| http.request(req) }
    res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
  end

  def humanize_secs(s)
    return "#{s}s" if s < 60
    return "#{s / 60}min" if s < 3600
    return "#{s / 3600}h" if s < 86_400
    d = s / 86_400
    h = (s % 86_400) / 3600
    h.positive? ? "#{d}d #{h}h" : "#{d}d"
  end

  def bytes(n)
    n = n.to_f
    return "0B" if n <= 0
    units = %w[B KB MB GB TB]
    i = [ (Math.log(n, 1024)).floor, units.size - 1 ].min
    "#{(n / 1024**i).round(i.zero? ? 0 : 1)}#{units[i]}"
  end

  def log(source, error)
    Rails.logger.warn("[HudPayloadService] #{source} falhou: #{error.class}: #{error.message}")
  end
end
