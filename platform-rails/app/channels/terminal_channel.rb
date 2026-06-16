require "socket"

class TerminalChannel < ApplicationCable::Channel
  def subscribed
    @container_id = params[:container_id]
    @endpoint     = params[:endpoint].presence || "unix:///var/run/docker.sock"
    @channel_name = "terminal_#{@container_id}_#{SecureRandom.hex(6)}"
    stream_from @channel_name
    start_terminal
  end

  def unsubscribed
    @running = false
    @reader_thread&.kill
    @socket&.close rescue nil
  end

  def input(data)
    @socket&.write(data["text"]) rescue nil
  end

  def resize(data)
    return unless @exec_id
    DockerClient.new(endpoint: @endpoint)
                .exec_resize(@exec_id, rows: data["rows"].to_i, cols: data["cols"].to_i) rescue nil
  end

  private

  def start_terminal
    client    = DockerClient.new(endpoint: @endpoint)
    exec_data = client.exec_create(@container_id, user: params[:user].presence)
    @exec_id  = exec_data&.dig("Id")
    return transmit(error: "Could not create exec session") unless @exec_id

    socket_path = @endpoint.sub(%r{^unix://}, "")
    @socket = UNIXSocket.new(socket_path)

    body    = %({"Detach":false,"Tty":true})
    request = "POST /v1.47/exec/#{@exec_id}/start HTTP/1.1\r\n" \
              "Host: localhost\r\n" \
              "Content-Type: application/json\r\n" \
              "Content-Length: #{body.bytesize}\r\n" \
              "Connection: close\r\n" \
              "\r\n" \
              "#{body}"
    @socket.write(request)

    loop { break if (line = @socket.gets).nil? || line == "\r\n" }

    @running = true
    @reader_thread = Thread.new do
      while @running
        chunk = @socket.readpartial(4096)
        ActionCable.server.broadcast(@channel_name, {
          output: chunk.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
        })
      end
    rescue EOFError, IOError, Errno::EBADF, Errno::ECONNRESET
      ActionCable.server.broadcast(@channel_name,
        { output: "\r\n\e[2;33m[session ended]\e[0m\r\n" })
    rescue => e
      ActionCable.server.broadcast(@channel_name,
        { output: "\r\n\e[31m[error: #{e.message}]\e[0m\r\n" })
    ensure
      @running = false
    end
  rescue => e
    transmit(error: "Terminal error: #{e.message}") rescue nil
  end
end
