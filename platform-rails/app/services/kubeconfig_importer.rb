require "yaml"
require "base64"

# Imports a full multi-context kubeconfig (upload/paste) into one Environment
# per context — "cluster/context" naming keeps the existing environment
# selector as the only "which cluster" UI (kubeconfig is just the format we
# import from, not a concept the rest of the app needs to know about).
class KubeconfigImporter
  Created = Struct.new(:context, :environment, :reachable, keyword_init: true)
  Skipped = Struct.new(:context, :reason, keyword_init: true)
  Result  = Struct.new(:created, :skipped, keyword_init: true)

  def self.call(yaml_content)
    new(yaml_content).call
  end

  def initialize(yaml_content)
    @config = YAML.safe_load(yaml_content.to_s, aliases: true) || {}
  end

  def call
    clusters = index_by_name(@config["clusters"], "cluster")
    users    = index_by_name(@config["users"], "user")

    created = []
    skipped = []

    Array(@config["contexts"]).each do |ctx|
      ctx_name     = ctx["name"]
      cluster_name = ctx.dig("context", "cluster")
      user_name    = ctx.dig("context", "user")
      cluster      = clusters[cluster_name]

      unless cluster
        skipped << Skipped.new(context: ctx_name, reason: "cluster \"#{cluster_name}\" not found in this kubeconfig")
        next
      end

      env_name = "#{cluster_name}/#{ctx_name}"
      if Environment.exists?(name: env_name)
        skipped << Skipped.new(context: ctx_name, reason: "environment \"#{env_name}\" already exists")
        next
      end

      env = build_environment(env_name, cluster, users[user_name])
      unless env.valid?
        skipped << Skipped.new(context: ctx_name, reason: env.errors.full_messages.join(", "))
        next
      end

      # Best-effort — a temporarily-unreachable cluster in a 3-context
      # kubeconfig shouldn't sink the other two; it's just flagged for the
      # admin instead of blocking the whole import.
      reachable = probe(env)
      env.save!
      created << Created.new(context: ctx_name, environment: env, reachable: reachable)
    end

    Result.new(created: created, skipped: skipped)
  end

  private

  def index_by_name(list, key)
    Array(list).each_with_object({}) { |item, acc| acc[item["name"]] = item[key] || {} }
  end

  def build_environment(name, cluster, user)
    attrs = {
      name: name,
      endpoint_type: "kubernetes",
      kube_api_url: cluster["server"],
      kube_ca_cert: decode64(cluster["certificate-authority-data"])
    }

    if user
      attrs[:kube_token_ciphertext] = user["token"] if user["token"].present?
      if user["client-certificate-data"].present? && user["client-key-data"].present?
        attrs[:kube_client_cert_ciphertext] = decode64(user["client-certificate-data"])
        attrs[:kube_client_key_ciphertext]  = decode64(user["client-key-data"])
      end
    end

    Environment.new(attrs)
  end

  def decode64(data)
    return nil if data.blank?
    Base64.decode64(data)
  end

  def probe(env)
    env.kube_client.version
    true
  rescue KubeClient::Error
    false
  end
end
