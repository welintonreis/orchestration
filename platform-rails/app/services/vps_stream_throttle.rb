# Limita quantas transferências SSH descartáveis (download / archive) correm ao
# mesmo tempo neste processo.
#
# Por que existe: em 2026-09-02 01:21 o navegador de arquivos disparou vários
# downloads em paralelo; cada um abre um Net::SFTP.start próprio (o pool não
# serve aqui — o cliente pode abandonar a transferência no meio e travar o
# mutex do pool). O handshake + decriptação de várias conexões simultâneas
# segurou o processo o bastante pra /up estourar os 5s do healthcheck três
# vezes seguidas, e o Swarm matou a task com exit 137.
#
# Slots vazam quando o cliente desconecta e o ensure do enumerator não roda —
# por isso cada slot tem prazo de validade em vez de ser um semáforo puro:
# um slot esquecido se cura sozinho em TTL, sem wedge permanente.
class VpsStreamThrottle
  MAX_CONCURRENT = Integer(ENV.fetch("VPS_MAX_CONCURRENT_STREAMS", 2))
  TTL            = Integer(ENV.fetch("VPS_STREAM_SLOT_TTL", 600)) # segundos

  SLOTS = {}
  LOCK  = Mutex.new

  class Busy < StandardError; end

  class << self
    # Executa o bloco ocupando um slot; levanta Busy se não houver vaga.
    def with_slot
      token = acquire or raise Busy, "transferências simultâneas no limite (#{MAX_CONCURRENT})"
      begin
        yield
      ensure
        release(token)
      end
    end

    # Para streams: o corpo da resposta é consumido depois da action retornar,
    # então o slot é liberado pelo próprio enumerator (ver release/1).
    def acquire
      LOCK.synchronize do
        prune
        return nil if SLOTS.size >= MAX_CONCURRENT

        token = SecureRandom.uuid
        SLOTS[token] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        token
      end
    end

    def release(token)
      LOCK.synchronize { SLOTS.delete(token) } if token
    end

    def active
      LOCK.synchronize { prune; SLOTS.size }
    end

    private

    def prune
      cutoff = Process.clock_gettime(Process::CLOCK_MONOTONIC) - TTL
      SLOTS.delete_if { |_, started| started < cutoff }
    end
  end
end
