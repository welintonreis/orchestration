require "net/http"
require "json"
require "uri"

class SeaweedfsService
  CONFIG_PATH_IN_CONTAINER = "/etc/seaweedfs/s3.json"
  FILER_HOSTS = ["seaweedfs_seaweedfs:8888", "seaweedfs:8888", "127.0.0.1:8888"].freeze

  def self.filer_request(path, method: :get, headers: {}, body: nil, form_data: nil)
    FILER_HOSTS.each do |host|
      url = URI("http://#{host}#{path}")
      req = case method
            when :get
              Net::HTTP::Get.new(url)
            when :post
              Net::HTTP::Post.new(url)
            when :delete
              Net::HTTP::Delete.new(url)
            end

      headers.each { |k, v| req[k] = v }
      req["Accept"] = "application/json" unless headers.key?("Accept")

      if body
        req.body = body
      elsif form_data
        req.set_form(form_data, "multipart/form-data")
      end

      begin
        http = Net::HTTP.new(url.host, url.port)
        http.open_timeout = 2
        http.read_timeout = 5
        res = http.request(req)
        return res
      rescue StandardError
        next
      end
    end
    nil
  end

  def self.seaweed_container_id
    client = DockerClient.new
    containers = client.containers(all: false)
    c = containers.find { |item| (item["Names"] || []).any? { |n| n.include?("seaweedfs") } }
    c&.dig("Id")
  rescue StandardError
    nil
  end

  def self.load_config
    cid = seaweed_container_id
    if cid.present?
      client = DockerClient.new
      out = client.exec_run_output(cid, ["cat", CONFIG_PATH_IN_CONTAINER])
      JSON.parse(out)
    else
      { "identities" => [] }
    end
  rescue StandardError => e
    { "error" => e.message, "identities" => [] }
  end

  def self.save_config(config)
    cid = seaweed_container_id
    return false if cid.blank?

    client = DockerClient.new
    json_str = JSON.pretty_generate(config)
    cmd = ["sh", "-c", "cat << 'EOF' > #{CONFIG_PATH_IN_CONTAINER}\n#{json_str}\nEOF"]
    client.exec_run_output(cid, cmd)

    if File.exist?("/root/docker/seaweedfs/s3.json")
      File.write("/root/docker/seaweedfs/s3.json", json_str) rescue nil
    end

    system("docker service update --force seaweedfs_seaweedfs >/dev/null 2>&1")
    true
  rescue StandardError => e
    Rails.logger.error("[SeaweedfsService] save_config error: #{e.message}")
    false
  end

  def self.list_buckets
    res = filer_request("/buckets/")
    if res && res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body) rescue {}
      entries = data["Entries"] || []
      buckets = entries.map { |e| e["FullPath"].to_s.sub(%r{^/buckets/}, "").sub(%r{/$}, "") }
      buckets = buckets.reject { |b| b.blank? || b == ".system" }
      return buckets if buckets.any?
    end

    # Fallback via container inspect / default
    ["whatsapp-media"]
  rescue StandardError
    ["whatsapp-media"]
  end

  def self.list_objects(bucket, prefix = "")
    clean_prefix = prefix.to_s.gsub(%r{^/+|/+$}, "")
    path = if clean_prefix.present?
             "/buckets/#{bucket}/#{clean_prefix}/"
           else
             "/buckets/#{bucket}/"
           end

    res = filer_request(path)
    return { "Path" => path, "Entries" => [] } unless res && res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body) rescue {}
    entries = data["Entries"] || []

    formatted_entries = entries.map do |e|
      full_path = e["FullPath"].to_s
      rel_path = full_path.sub(%r{^/buckets/#{bucket}/?}, "")
      name = full_path.split("/").last
      is_dir = (e["Mode"].to_i >= 2147483648) || (e["chunks"].nil? && e["FileSize"].to_i == 0)

      {
        "name" => name,
        "full_path" => full_path,
        "rel_path" => rel_path,
        "size" => e["FileSize"].to_i,
        "mtime" => e["Mtime"],
        "mime" => e["Mime"].presence || (is_dir ? "directory" : "application/octet-stream"),
        "is_dir" => is_dir
      }
    end

    {
      "Path" => data["Path"] || path,
      "prefix" => clean_prefix,
      "bucket" => bucket,
      "Entries" => formatted_entries
    }
  rescue StandardError => e
    { "error" => e.message, "Path" => path, "Entries" => [] }
  end

  def self.get_object(bucket, path)
    clean_path = path.to_s.gsub(%r{^/+}, "")
    filer_request("/buckets/#{bucket}/#{clean_path}", headers: { "Accept" => "*/*" })
  end

  def self.create_bucket(bucket_name)
    clean_name = bucket_name.to_s.strip.gsub(/[^a-zA-Z0-9.\-_]/, "")
    return false if clean_name.blank?

    res = filer_request("/buckets/#{clean_name}/", method: :post)
    res && (res.code.to_i.between?(200, 299) || res.code.to_i == 302)
  end

  def self.delete_object(bucket, path)
    clean_path = path.to_s.gsub(%r{^/+}, "")
    target = "/buckets/#{bucket}/#{clean_path}"
    target += "?recursive=true" if clean_path.end_with?("/")

    res = filer_request(target, method: :delete)
    res && res.code.to_i.between?(200, 299)
  end

  def self.upload_file(bucket, folder_path, file_param)
    clean_folder = folder_path.to_s.gsub(%r{^/+|/+$}, "")
    target_path = clean_folder.present? ? "/buckets/#{bucket}/#{clean_folder}/" : "/buckets/#{bucket}/"

    # Upload via Net::HTTP multipart
    FILER_HOSTS.each do |host|
      url = URI("http://#{host}#{target_path}#{URI.encode_www_form_component(file_param.original_filename)}")
      req = Net::HTTP::Post.new(url)
      req.body = file_param.read
      req["Content-Type"] = file_param.content_type || "application/octet-stream"

      begin
        http = Net::HTTP.new(url.host, url.port)
        http.open_timeout = 3
        http.read_timeout = 15
        res = http.request(req)
        return true if res && res.code.to_i.between?(200, 299)
      rescue StandardError
        next
      end
    end
    false
  end
end
