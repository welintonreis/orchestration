module Swarm
  class DbBackupsController < ApplicationController
    include SwarmGuard

    PER_PAGE = 50

    def index
      rows if turbo_frame_request?
    end

    def rows
      @result        = WalgInspectorService.call
      @history       = BackupSnapshot.where(server: "master").recent_first.limit(90)
      @total_backups = @result.backups.size
      @page          = current_page
      @backups_page  = @result.backups[page_offset, PER_PAGE] || []
      render "rows", layout: false
    end

    private

    def current_page = [params[:page].to_i, 1].max
    def page_offset  = (current_page - 1) * PER_PAGE
  end
end
