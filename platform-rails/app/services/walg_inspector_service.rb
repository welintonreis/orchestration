require "json"

# Introspecção do estado do WAL-G no container postgres-master, via Docker
# exec (mesmo mecanismo de SeaweedfsService/ContainersController — sem gem
# nova, sem Open3). Só leitura: nenhum comando de escrita/delete roda aqui.
class WalgInspectorService
  Backup = Struct.new(:name, :type, :time, :wal_file_name, keyword_init: true)

  Result = Struct.new(:ok, :backups, :total_bytes, :object_count, :error, keyword_init: true) do
    def ok? = ok
  end

  R2_ENDPOINT  = "https://85c7ebc56fe4c6aca4939b68af878c04.r2.cloudflarestorage.com"
  R2_BUCKET    = "redhusky-wal-archive"
  WALG_SUBPATH = "pg17/7641750416482078763"

  def self.call = new.call

  def call
    client = DockerClient.new
    cid = master_container_id(client)
    return Result.new(ok: false, backups: [], error: "container postgres-master não encontrado ou parado") if cid.blank?

    Result.new(ok: true, backups: backup_list(client, cid), **bucket_size(client))
  rescue => e
    Result.new(ok: false, backups: [], error: e.message)
  end

  private

  def master_container_id(client)
    client.containers(all: false).find { |c| (c["Names"] || []).any? { |n| n.include?("postgres-master") } }&.dig("Id")
  end

  def backup_list(client, cid)
    raw = client.exec_run_output(cid, ["sh", "-c", walg_env_prefix + "wal-g backup-list --json"])
    # wal-g imprime uma linha "INFO: ... [default]" antes do array JSON —
    # um índice de "[" ingênuo pega o colchete errado (o "[default]" do log
    # de INFO). O JSON sempre vem sozinho numa linha que começa com "[".
    json_line = raw.lines.map(&:strip).find { |l| l.start_with?("[") }
    JSON.parse(json_line || "[]").map { |b|
      Backup.new(name: b["backup_name"], type: b["backup_name"].include?("_D_") ? "DELTA" : "FULL",
                 time: b["time"], wal_file_name: b["wal_file_name"])
    }.sort_by(&:time).reverse
  end

  # amazon/aws-cli descartável criado pelo orchestration (postgres-master
  # não tem docker.sock montado, confirmado) — cria, espera terminar, lê
  # log, remove. Credenciais embutidas no cmd porque container_create do
  # DockerClient não aceita env (menor diff que mudar um método
  # compartilhado por causa desta tela).
  def bucket_size(client)
    # amazon/aws-cli tem ENTRYPOINT fixo ["/usr/local/bin/aws"] — sem
    # sobrescrever, "sh -c ..." vira um argumento inválido pro próprio aws
    # ("invalid choice 'sh'"). entrypoint: aqui troca isso por um shell de
    # verdade, só pra este container descartável.
    created = client.container_create(
      image: "amazon/aws-cli",
      entrypoint: ["sh", "-c"],
      cmd: [<<~SH]
        export AWS_ACCESS_KEY_ID=#{r2_key} AWS_SECRET_ACCESS_KEY=#{r2_secret} AWS_DEFAULT_REGION=auto
        aws s3 --endpoint-url=#{R2_ENDPOINT} ls s3://#{R2_BUCKET}/#{WALG_SUBPATH}/ --recursive --summarize
      SH
    )
    id = created["Id"]
    client.container_start(id)
    wait_for_exit(client, id, timeout: 30)
    out = client.container_logs(id, tail: 20)
    client.container_remove(id, force: true)
    parse_summarize(out)
  rescue
    { total_bytes: nil, object_count: nil }
  end

  def wait_for_exit(client, id, timeout:)
    deadline = Time.now + timeout
    sleep 0.5 until client.container(id).dig("State", "Status") == "exited" || Time.now > deadline
  end

  def parse_summarize(out)
    { total_bytes: out[/Total Size:\s+(\d+)/, 1]&.to_i, object_count: out[/Total Objects:\s+(\d+)/, 1]&.to_i }
  end

  def walg_env_prefix
    "export AWS_ACCESS_KEY_ID=$(cat /run/secrets/r2_access_key_id); " \
    "export AWS_SECRET_ACCESS_KEY=$(cat /run/secrets/r2_secret_access_key); " \
    "export WALG_S3_PREFIX=s3://#{R2_BUCKET}/#{WALG_SUBPATH}; " \
    "export AWS_ENDPOINT=#{R2_ENDPOINT}; export AWS_S3_FORCE_PATH_STYLE=true; export AWS_REGION=auto; "
  end

  def r2_key    = @r2_key    ||= File.read("/run/secrets/r2_access_key_id").strip
  def r2_secret = @r2_secret ||= File.read("/run/secrets/r2_secret_access_key").strip
end
