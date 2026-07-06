module Kube
  class PodsController < ApplicationController
    include RequireKubernetes

    def index
      load_namespaces
      @pods = current_kube_client.pods(ns: @namespace)
    rescue KubeClient::Error => e
      @pods = []
      flash.now[:alert] = "Kubernetes error: #{e.message}"
    end

    def logs
      @pod_name = params[:name]
      @tail = (params[:tail] || 200).to_i
      @logs = current_kube_client.pod_logs(ns: @namespace, name: @pod_name, container: params[:container], tail: @tail)
    rescue KubeClient::Error => e
      @logs = "Error fetching logs: #{e.message}"
    end

    def destroy
      current_kube_client.delete_pod(ns: @namespace, name: params[:name])
      redirect_to kube_pods_path(ns: @namespace), notice: "Pod #{params[:name]} deleted."
    rescue KubeClient::Error => e
      redirect_to kube_pods_path(ns: @namespace), alert: "Error: #{e.message}"
    end

    def terminal
      @pod_name = params[:name]
    end

    # Mirrors ContainersController#ttyd_ws — same rack-hijack + TtydManager
    # pattern, pointed at a kubectl exec command instead of docker exec.
    def ttyd_ws
      return head :bad_request unless request.env["HTTP_UPGRADE"].to_s.downcase == "websocket"

      session = TtydManager.instance.start_kubernetes(
        params[:name], environment: active_environment, namespace: @namespace,
        container: params[:container]
      )

      hijack = request.env["rack.hijack"]
      return head :internal_server_error unless hijack
      hijack.call
      browser = request.env["rack.hijack_io"]
      ttyd    = TCPSocket.new(TtydManager::BIND_ADDR, session.port)

      enable_nodelay(browser)
      enable_nodelay(ttyd)
      ttyd.write(ttyd_handshake(request.env))

      up   = Thread.new { pump(browser, ttyd) rescue nil; close_quietly(ttyd) }
      down = Thread.new { pump(ttyd, browser) rescue nil; close_quietly(browser) }
      up.join
      down.join
    ensure
      close_quietly(browser)
      close_quietly(ttyd)
      TtydManager.instance.stop(session&.token) rescue nil
      head :ok
    end

    private

    def ttyd_handshake(env)
      key      = env["HTTP_SEC_WEBSOCKET_KEY"]
      version  = env["HTTP_SEC_WEBSOCKET_VERSION"].presence || "13"
      protocol = env["HTTP_SEC_WEBSOCKET_PROTOCOL"].presence || "tty"
      [
        "GET /ws HTTP/1.1",
        "Host: #{TtydManager::BIND_ADDR}",
        "Upgrade: websocket",
        "Connection: Upgrade",
        "Sec-WebSocket-Key: #{key}",
        "Sec-WebSocket-Version: #{version}",
        "Sec-WebSocket-Protocol: #{protocol}",
        "", ""
      ].join("\r\n")
    end

    def pump(src, dst)
      loop { dst.write(src.readpartial(16_384)) }
    rescue EOFError, IOError, Errno::EBADF, Errno::ECONNRESET
      nil
    end

    def enable_nodelay(io)
      io.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
    rescue StandardError
      nil
    end

    def close_quietly(io)
      io&.close
    rescue IOError, Errno::EBADF
      nil
    end
  end
end
