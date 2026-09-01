# frozen_string_literal: true

# 9router already has its own login + quota dashboard (router.redhusky.com.br/dashboard/quota).
# ponytail: embed it instead of re-implementing its auth/usage API — no X-Frame-Options set upstream.
class AiQuotaController < ApplicationController
  ROUTER_URL = "https://router.redhusky.com.br/dashboard/quota"

  def index
    @router_url = ROUTER_URL
  end
end
