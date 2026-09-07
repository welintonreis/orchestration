module Swarm
  class DbClusterController < ApplicationController
    include SwarmGuard

    def index
      rows if turbo_frame_request?
    end

    def rows
      inspector = DbClusterInspectorService.new
      redis     = RedisInspectorService.new
      rabbitmq  = RabbitmqInspectorService.new

      redis_rows    = redis.call
      rabbitmq_rows = rabbitmq.call

      @db_rows         = inspector.call + redis_rows + rabbitmq_rows
      @host_stats      = inspector.host_stats.index_by(&:server)
      @redis_summary   = redis.summary(redis_rows)
      @rabbitmq_summary = rabbitmq.summary(rabbitmq_rows)
      render "rows", layout: false
    end
  end
end
