class LogsChannel < ApplicationCable::Channel
  HEADER_SIZE = 8

  def subscribed
    @container_id = params[:container_id]
    @tail         = (params[:tail] || 200).to_i
    @endpoint     = params[:endpoint].presence || "unix:///var/run/docker.sock"
    @timestamps   = params[:timestamps] == true || params[:timestamps] == "true"
    @stop         = false
    @buffer       = +""

    @stream_thread = Thread.new do
      DockerClient.new(endpoint: @endpoint)
                  .container_logs(@container_id, tail: @tail, timestamps: @timestamps) do |chunk|
        break if @stop
        @buffer << chunk.b
        while @buffer.bytesize >= HEADER_SIZE
          size = @buffer.byteslice(4, 4).unpack1("N")
          break if @buffer.bytesize < HEADER_SIZE + size
          payload = @buffer.byteslice(HEADER_SIZE, size).to_s
          @buffer = @buffer.byteslice(HEADER_SIZE + size, @buffer.bytesize) || +""
          next if payload.empty?
          text = payload.encode("UTF-8", "ASCII-8BIT", invalid: :replace, undef: :replace)
          transmit({ chunk: text })
        end
      end
    rescue => e
      transmit({ error: e.message }) rescue nil
    end
  end

  def unsubscribed
    @stop = true
    @stream_thread&.kill
    @stream_thread = nil
  end
end
