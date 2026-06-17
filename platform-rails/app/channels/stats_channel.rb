class StatsChannel < ApplicationCable::Channel
  POLL_INTERVAL = 2

  # Polls a snapshot every 2s instead of holding dockerd's continuous
  # stats stream (stream=1) open for the page's lifetime. /containers
  # renders one of these per visible running container row, torn down
  # and recreated via Thread#kill on every filter/page-size change —
  # with many rows visible at once, the resulting churn of simultaneous
  # open+killed streaming connections to dockerd was bogging the daemon
  # down for every other request app-wide. A short poll loop is cheap
  # per-tick and its Thread#kill only ever interrupts a sleep, never a
  # blocking read mid-stream.
  def subscribed
    @container_id = params[:container_id]
    @endpoint     = params[:endpoint].presence || "unix:///var/run/docker.sock"
    @stop         = false

    @poll_thread = Thread.new do
      client = DockerClient.new(endpoint: @endpoint)
      until @stop
        begin
          data = client.container_stats_snapshot(@container_id)
          transmit({ stats: data }) unless @stop
        rescue => e
          transmit({ error: e.message }) rescue nil
        end
        sleep POLL_INTERVAL
      end
    end
  end

  def unsubscribed
    @stop = true
    @poll_thread&.kill
    @poll_thread = nil
  end
end
