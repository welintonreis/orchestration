require "pg"
require "resolv"

# Introspecção ao vivo do cluster Postgres (master + analytics + development)
# via SQL direto — não passa pelo HAProxy/PgBouncer.
#
# ponytail: bypass deliberado do pooler. PgBouncer só tem aliases fixos por
# app ("orchestration", "analytics", curinga "*" pro development); listar
# TODOS os bancos de um host via pg_database exige uma conexão de
# superusuário direta no container, não uma conexão através de um alias que
# já assume o banco de destino.
class DbClusterInspectorService
  # type: "banco" (Postgres, default), "cache" (Redis) ou "channel"
  # (RabbitMQ) — ver RedisInspectorService / RabbitmqInspectorService, que
  # reaproveitam este mesmo Struct pra caber na mesma tabela.
  DbRow = Struct.new(:type, :server, :database, :owner, :login_roles_count,
                      :procedures_count, :tables_count, :estimated_rows,
                      :growth_7d, :growth_30d, :growth_365d, keyword_init: true) do
    def type = self[:type] || "banco"
  end

  HostStat = Struct.new(:server, :ip, :port, :db_count, :tables_count,
                         :procedures_count, :roles_count, :vector_version,
                         keyword_init: true)

  # Bancos que entram na tabela detalhada (excluída "read", réplica idêntica
  # ao master — apareceria duplicada sem agregar nada novo).
  HOSTS = {
    "master"    => { host: "postgres-master" },
    "analytics" => { host: "postgres-analytics" }
  }.freeze

  # Todos os 4 nós físicos, pra topologia (contadores agregados por host).
  ALL_HOSTS = HOSTS.merge(
    "read"        => { host: "postgres-read" },
    "development" => { host: "postgres-development" }
  ).freeze

  PORT = 5432

  def self.call = new.call

  # call e host_stats reaproveitam a mesma instância (e o mesmo @db_rows
  # memoizado) — ver Swarm::DbClusterController#rows. Chamar via .call/
  # .host_stats na classe direto criaria duas instâncias e consultaria
  # master+analytics duas vezes.
  def call
    @db_rows ||= HOSTS.flat_map { |server, cfg| databases_for(server, cfg) }
  end

  # Um HostStat por nó — usado nas caixinhas da topologia. "read" reaproveita
  # os agregados de "master" (réplica física, mesmos dados) em vez de
  # reconsultar tabela por tabela de novo.
  def host_stats
    rows_by_server = call.group_by(&:server)
    master_agg = aggregate("master", rows_by_server["master"] || [])

    ALL_HOSTS.map do |server, cfg|
      base =
        case server
        when "master"    then master_agg
        when "analytics" then aggregate(server, rows_by_server["analytics"] || [])
        when "read"      then master_agg.dup
        else aggregate(server, databases_for(server, cfg))
        end

      base.server = server
      base.ip, base.port = resolve(cfg[:host])
      base.vector_version = vector_version(cfg[:host])
      base
    end
  end

  private

  def aggregate(server, rows)
    HostStat.new(
      server: server,
      db_count: rows.size,
      tables_count: rows.sum(&:tables_count),
      procedures_count: rows.sum(&:procedures_count),
      roles_count: rows.first&.login_roles_count || 0
    )
  end

  def resolve(host)
    [Resolv.getaddress(host), PORT]
  rescue Resolv::ResolvError
    [nil, PORT]
  end

  def vector_version(host)
    conn = connect(host, "postgres")
    conn.exec("select default_version from pg_available_extensions where name = 'vector'").getvalue(0, 0)
  rescue
    nil
  ensure
    conn&.close
  end

  def databases_for(server, cfg)
    conn = connect(cfg[:host], "postgres")
    dbs = conn.exec(<<~SQL).values.flatten
      select datname from pg_database
      where datistemplate = false and datname not in ('postgres')
    SQL
    dbs.map { |db| introspect(server, cfg[:host], db) }
  ensure
    conn&.close
  end

  def introspect(server, host, db)
    conn = connect(host, db)

    owner = conn.exec_params(
      "select pg_get_userbyid(datdba) from pg_database where datname = $1", [db]
    ).getvalue(0, 0)

    login_roles = conn.exec(
      "select count(*) from pg_roles where rolcanlogin = true"
    ).getvalue(0, 0).to_i

    procedures = conn.exec(<<~SQL).getvalue(0, 0).to_i
      select count(*) from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
    SQL

    tables = conn.exec(<<~SQL).getvalue(0, 0).to_i
      select count(*) from pg_stat_user_tables where schemaname = 'public'
    SQL

    estimated_rows = conn.exec(<<~SQL).getvalue(0, 0).to_i
      select coalesce(sum(n_live_tup), 0) from pg_stat_user_tables where schemaname = 'public'
    SQL

    DbRow.new(
      server: server, database: db, owner: owner,
      login_roles_count: login_roles, procedures_count: procedures,
      tables_count: tables, estimated_rows: estimated_rows,
      growth_7d:   growth_pct(server, db, estimated_rows, 7.days.ago),
      growth_30d:  growth_pct(server, db, estimated_rows, 30.days.ago),
      growth_365d: growth_pct(server, db, estimated_rows, 365.days.ago)
    )
  ensure
    conn&.close
  end

  def growth_pct(server, db, current, target_time)
    baseline = DbClusterSnapshot.nearest_to(server, db, target_time)
    return nil if baseline.nil? || baseline.captured_at > target_time + 2.days
    return nil if baseline.row_count.zero?

    ((current - baseline.row_count).to_f / baseline.row_count * 100).round(1)
  end

  def connect(host, dbname)
    PG.connect(host: host, port: PORT, dbname: dbname,
               user: sa_user, password: sa_password, connect_timeout: 3)
  end

  def sa_user     = @sa_user     ||= File.read("/run/secrets/pg_user").strip
  def sa_password = @sa_password ||= File.read("/run/secrets/pg_password").strip
end
