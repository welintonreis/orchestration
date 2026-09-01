require "test_helper"

class SecurityControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in(users(:admin_user)) }

  # index must not run the audit: it scans /host/proc and hits the Docker
  # socket, which is exactly what used to stall the page before any paint.
  test "GET /security renders the shell without running the audit" do
    with_stub(SecurityAudit, :new, ->(*) { raise "SecurityAudit não pode rodar no index" }) do
      get security_path
      assert_response :success
      assert_select "turbo-frame#security-content[src=?]", rows_security_path
      assert_select "[aria-busy='true']"
    end
  end

  # A dead Docker socket degrades the port map to empty, never a 500.
  test "GET /security/rows survives an unreachable daemon" do
    with_stub(DockerClient, :new, ->(*) { raise DockerClient::ConnectionError }) do
      get rows_security_path
      assert_response :success
      assert_select "turbo-frame#security-content"
    end
  end

  test "GET /security/rows renders Fase 2 placeholder when collector hasn't run" do
    with_security_path("/nonexistent/state.json") do
      get rows_security_path
      assert_response :success
      assert_match "Fase 2 indisponível", response.body
    end
  end

  test "GET /security/rows renders brute-force, fail2ban and login sections when host_state is present" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "state.json")
      File.write(path, {
        ssh_brute_force: { total_failed_attempts: 42, top_ips: [ { ip: "45.148.10.240", attempts: 30,
                                                                    country: "Netherlands", country_code: "NL",
                                                                    city: "Amsterdam", lat: 52.37, lon: 4.9 } ] },
        fail2ban: { running: true, jails: [ { name: "sshd", currently_failed: 1, total_failed: 9,
                                              currently_banned: 2, total_banned: 4, banned_ips: [ "45.148.10.240" ] } ] },
        firewall: { ufw_active: false, docker_user_drop_rules: 0, nft_tables: [ "inet f2b-table" ] },
        accepted_logins: [ { time: "2026-07-01T00:40:14+02:00", method: "publickey", user: "root",
                             ip: "38.10.153.3", port: 13856, external: true } ],
        collected_at: "2026-07-01T01:00:00Z"
      }.to_json)

      with_security_path(path) do
        get rows_security_path
        assert_response :success
        assert_match "45.148.10.240", response.body
        assert_match "(externo)", response.body
        assert_select "[data-controller='security-map']"
      end
    end
  end

  test "GET /security/rows flags containers with suspicious filesystem drift" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "container-diff.json")
      File.write(path, {
        collected_at: "2026-07-01T01:00:00Z",
        containers: [
          { name: "metabase_metabase", image: "metabase/metabase:v0.51.4", total_changes: 34,
            critical: [ { type: "C", path: "/etc/passwd" }, { type: "C", path: "/etc/shadow" } ] },
          { name: "kafka_kafka-connect", image: "confluentinc/cp-kafka-connect:7.6.0", total_changes: 12, critical: [] }
        ]
      }.to_json)

      with_container_diff_path(path) do
        get rows_security_path
        assert_response :success
        assert_match "metabase_metabase", response.body
        assert_match "/etc/passwd", response.body
        assert_no_match "kafka_kafka-connect", response.body
      end
    end
  end

  private

  def with_security_path(path)
    old = ENV["HOST_SECURITY_PATH"]
    ENV["HOST_SECURITY_PATH"] = path
    yield
  ensure
    ENV["HOST_SECURITY_PATH"] = old
  end

  def with_container_diff_path(path)
    old = ENV["CONTAINER_DIFF_PATH"]
    ENV["CONTAINER_DIFF_PATH"] = path
    yield
  ensure
    ENV["CONTAINER_DIFF_PATH"] = old
  end
end
