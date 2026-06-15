class StatsChannel < ApplicationCable::Channel
  def subscribed
    @container_id = params[:container_id]
    @endpoint     = params[:endpoint].presence || "unix:///var/run/docker.sock"
    @stop         = false

    @stream_thread = Thread.new do
      DockerClient.new(endpoint: @endpoint).container_stats(@container_id) do |data|
        break if @stop
        transmit({ stats: data })
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
