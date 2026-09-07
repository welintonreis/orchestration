require "net/http"
require "json"
require "resolv"

# Introspecção do RabbitMQ via API HTTP de management (plugin já habilitado
# na imagem *-management). Mapeamento pro mesmo formato de linha da tabela:
# vhost = banco, fila = tabela, mensagens = registro.
class RabbitmqInspectorService
  DbRow = DbClusterInspectorService::DbRow

  HOST = "rabbitmq"
  PORT = 15672      # management API, usado só pra introspecção
  AMQP_PORT = 5672  # porta real de dados (a que aparece na caixinha)

  def self.call = new.call

  def call
    queues = get("/api/queues")
    return [] unless queues

    queues.group_by { |q| q["vhost"] }.map do |vhost, vqueues|
      DbRow.new(
        type: "channel", server: "rabbitmq", database: vhost,
        owner: nil, login_roles_count: vqueues.sum { |q| q["consumers"].to_i },
        procedures_count: nil, tables_count: vqueues.size,
        estimated_rows: vqueues.sum { |q| q["messages"].to_i },
        growth_7d: nil, growth_30d: nil, growth_365d: nil
      )
    end
  rescue => e
    Rails.logger.warn("RabbitmqInspectorService failed: #{e.message}")
    []
  end

  def summary(rows)
    ip = Resolv.getaddress(HOST)
    { ip: ip, port: AMQP_PORT, vhosts: rows.size, queues: rows.sum { |r| r.tables_count.to_i },
      messages: rows.sum { |r| r.estimated_rows.to_i } }
  rescue Resolv::ResolvError
    { ip: nil, port: AMQP_PORT, vhosts: rows.size, queues: rows.sum { |r| r.tables_count.to_i },
      messages: rows.sum { |r| r.estimated_rows.to_i } }
  end

  private

  def get(path)
    uri = URI("http://#{HOST}:#{PORT}#{path}")
    req = Net::HTTP::Get.new(uri)
    req.basic_auth(user, password)
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 5) { |http| http.request(req) }
    JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
  end

  def user     = ENV.fetch("RABBITMQ_USER", "welintonreis")
  def password = ENV.fetch("RABBITMQ_PASSWORD")
end
