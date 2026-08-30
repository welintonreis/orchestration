require "net/http"
require "json"
require "uri"

class SeaweedfsService
  CONFIG_FILE = "/root/docker/seaweedfs/s3.json"
  ENV_FILE    = "/root/docker/seaweedfs/.env"
  S3_ENDPOINT = "http://172.18.0.1:8333"

  def self.load_config
    if File.exist?(CONFIG_FILE)
      JSON.parse(File.read(CONFIG_FILE))
    else
      { "identities" => [] }
    end
  rescue StandardError => e
    { "error" => e.message, "identities" => [] }
  end

  def self.save_config(config)
    File.write(CONFIG_FILE, JSON.pretty_generate(config))
    # Reiniciar serviço seaweedfs para recarregar identidades s3.json
    system("docker service update --force seaweedfs_seaweedfs >/dev/null 2>&1")
    true
  rescue StandardError => e
    false
  end

  def self.list_buckets
    # SeaweedFS expõe volumes/buckets via /admin/s3 ou S3 API direta
    buckets = []
    data_dir = "/var/lib/docker/volumes/seaweedfs_seaweedfs_data/_data/buckets"
    if Dir.exist?(data_dir)
      buckets = Dir.children(data_dir).select { |f| File.directory?(File.join(data_dir, f)) }
    end
    buckets
  rescue StandardError
    []
  end
end
