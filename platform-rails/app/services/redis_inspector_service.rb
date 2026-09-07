require "socket"
require "resolv"

# Introspecção mínima do Redis via protocolo RESP cru (sem gem redis — só
# precisamos de AUTH + INFO keyspace, não vale a pena a dependência).
# ponytail: parser RESP simplificado, cobre só os tipos de reply que AUTH/
# INFO retornam (simple string, bulk string, error) — não é um client Redis
# de propósito geral.
class RedisInspectorService
  DbRow = DbClusterInspectorService::DbRow

  HOST = "redis"
  PORT = 6379

  def self.call = new.call

  def call
    info = fetch_keyspace_info
    info.map do |db_index, stats|
      DbRow.new(
        type: "cache", server: "redis", database: db_index,
        owner: nil, login_roles_count: nil, procedures_count: nil,
        tables_count: nil, estimated_rows: stats[:keys],
        growth_7d: nil, growth_30d: nil, growth_365d: nil
      )
    end
  rescue => e
    Rails.logger.warn("RedisInspectorService failed: #{e.message}")
    []
  end

  # Resumo pra caixinha da topologia — sem custo extra: reaproveita a mesma
  # consulta que #call já fez, se tiver sido chamada antes na instância.
  def summary(rows)
    ip = Resolv.getaddress(HOST)
    { ip: ip, port: PORT, dbs_in_use: rows.size, total_keys: rows.sum { |r| r.estimated_rows.to_i } }
  rescue Resolv::ResolvError
    { ip: nil, port: PORT, dbs_in_use: rows.size, total_keys: rows.sum { |r| r.estimated_rows.to_i } }
  end

  private

  # "# Keyspace\ndb0:keys=25,expires=23,avg_ttl=...\n" → só os DBs com uso.
  def fetch_keyspace_info
    raw = redis_command("INFO", "keyspace")
    raw.lines.each_with_object({}) do |line, acc|
      next unless line.start_with?("db")
      db, rest = line.strip.split(":", 2)
      keys = rest[/keys=(\d+)/, 1].to_i
      acc[db] = { keys: keys }
    end
  end

  def redis_command(*args)
    sock = TCPSocket.new(HOST, PORT)
    write_command(sock, "AUTH", password)
    read_reply(sock)
    write_command(sock, *args)
    read_reply(sock)
  ensure
    sock&.close
  end

  def write_command(sock, *args)
    sock.write("*#{args.size}\r\n#{args.map { |a| "$#{a.bytesize}\r\n#{a}\r\n" }.join}")
  end

  def read_reply(sock)
    line = sock.gets("\r\n")
    case line[0]
    when "+" then line[1..-3]
    when "-" then raise line[1..-3]
    when "$"
      len = line[1..-3].to_i
      return nil if len == -1
      data = sock.read(len)
      sock.read(2)
      data
    else
      line
    end
  end

  def password = @password ||= File.read("/run/secrets/redis_password").strip
end
