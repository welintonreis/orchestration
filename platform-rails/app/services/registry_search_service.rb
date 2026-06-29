require "json"

# Searches public container registries.
# Returns array of result hashes with keys:
#   name, full_name, description, stars, pulls, official, registry_url
class RegistrySearchService
  TIMEOUT = { connect_timeout: 5, read_timeout: 10 }.freeze

  Result = Struct.new(:name, :full_name, :description, :stars, :pulls, :official, :registry_url, keyword_init: true)

  def self.call(registry, query)
    new(registry).search(query)
  end

  def initialize(registry)
    @registry = registry
  end

  def search(query)
    return [] if query.blank?
    case @registry.api_type
    when "docker_hub" then search_docker_hub(query)
    when "quay"       then search_quay(query)
    when "generic_v2" then search_v2_catalog(query)
    else []
    end
  rescue => e
    Rails.logger.warn("[RegistrySearchService] #{@registry.name}: #{e.message}")
    []
  end

  private

  def search_docker_hub(query)
    url  = "https://hub.docker.com/v2/search/repositories/"
    resp = Excon.get(url,
      query:   { query: query, page_size: 25 },
      headers: { "Accept" => "application/json" },
      **TIMEOUT
    )
    data = JSON.parse(resp.body)
    Array(data["results"]).map do |r|
      Result.new(
        name:         r["repo_name"],
        full_name:    r["repo_name"],
        description:  r["short_description"].to_s.truncate(120),
        stars:        r["star_count"].to_i,
        pulls:        r["pull_count"].to_i,
        official:     r["is_official"],
        registry_url: "docker.io"
      )
    end
  end

  def search_quay(query)
    resp = Excon.get("https://quay.io/api/v1/find/repositories",
      query:   { query: query, includeUsage: true, limit: 25 },
      headers: { "Accept" => "application/json" },
      **TIMEOUT
    )
    data = JSON.parse(resp.body)
    Array(data["results"]).map do |r|
      full = "#{r["namespace"]["name"]}/#{r["name"]}"
      Result.new(
        name:         r["name"],
        full_name:    full,
        description:  r["description"].to_s.truncate(120),
        stars:        0,
        pulls:        r.dig("popularity").to_i,
        official:     false,
        registry_url: "quay.io"
      )
    end
  end

  def search_v2_catalog(query)
    base = @registry.url.sub(%r{/+$}, "")
    resp = Excon.get("#{base}/v2/_catalog",
      query:   { n: 100 },
      headers: { "Accept" => "application/json" },
      **TIMEOUT
    )
    data = JSON.parse(resp.body)
    Array(data["repositories"])
      .select { |r| query.blank? || r.downcase.include?(query.downcase) }
      .first(25)
      .map do |repo|
        Result.new(
          name:         repo,
          full_name:    repo,
          description:  "",
          stars:        0,
          pulls:        0,
          official:     false,
          registry_url: URI.parse(base).host
        )
      end
  end
end
