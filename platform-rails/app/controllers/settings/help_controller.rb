module Settings
  class HelpController < ApplicationController
    def index
      @version = "1.0.0"
      @docker_info = current_docker_client.info rescue {}
    end
  end
end
