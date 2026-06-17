# Docker's /system/df is expensive (walks every image/volume to compute
# usage — ~14s on hosts with a few dozen images). A flat-TTL cache still
# pays that cost in full once the TTL expires. Stale-while-revalidate
# serves the last known value immediately and refreshes it in the
# background, so a request only blocks on the slow call once (cold cache).
module DockerCache
  extend ActiveSupport::Concern

  FRESH_FOR    = 20.seconds
  HARD_EXPIRY  = 5.minutes
  REFRESH_LOCK = 30.seconds

  def cached_system_df(type)
    key        = "docker_system_df/#{type}/#{active_environment&.id}"
    fresh_key  = "#{key}/fresh_until"
    lock_key   = "#{key}/refreshing"

    cached = Rails.cache.read(key)
    if cached
      stale = Rails.cache.read(fresh_key).nil?
      if stale && Rails.cache.write(lock_key, true, expires_in: REFRESH_LOCK, unless_exist: true)
        endpoint = docker_endpoint
        Thread.new do
          fresh = DockerClient.new(endpoint: endpoint).system_df(type: type)
          Rails.cache.write(key, fresh, expires_in: HARD_EXPIRY)
          Rails.cache.write(fresh_key, true, expires_in: FRESH_FOR)
        rescue
          nil
        ensure
          Rails.cache.delete(lock_key)
        end
      end
      return cached
    end

    result = current_docker_client.system_df(type: type)
    Rails.cache.write(key, result, expires_in: HARD_EXPIRY)
    Rails.cache.write(fresh_key, true, expires_in: FRESH_FOR)
    result
  end
end
