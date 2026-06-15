class MetricsController < ApplicationController
  def latest
    @latest_metric = HostMetric.latest
    @metrics_24h   = HostMetric.last_24h.order(:created_at)
    render layout: false
  end
end
