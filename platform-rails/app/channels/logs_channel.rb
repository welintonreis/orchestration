class LogsChannel < ApplicationCable::Channel
  def subscribed
    @container_id = params[:container_id]
    @tail         = (params[:tail] || 200).to_i
    @endpoint     = params[:endpoint].presence || "unix:///var/run/docker.sock"
    @stop         = false

    @stream_thread = Thread.new do
      DockerClient.new(endpoint: @endpoint).container_logs(@container_id, tail: @tail) do |chunk|
        break if @stop
        transmit({ chunk: chunk })
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
