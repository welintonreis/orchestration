module Internal
  # Internal::HudController — resumo da orelhinha de desktop.
  #
  # Contrato em 00_docs/hud-contract.md do repo redhusky-hud. Máquina-a-máquina:
  # sem sessão, sem CSRF, sem flash — por isso ActionController::API e não a
  # ApplicationController (que carrega Authentication/Authorization).
  #
  # Fronteira: o desktop NÃO é confiável.
  #   - token Bearer por dispositivo, guardado como digest, revogável;
  #   - só leitura, e só do resumo que a pill desenha;
  #   - nada de Docker/exec/scale por aqui — o HUD é consciência, ação é no painel.
  class HudController < ActionController::API
    STALE_AFTER = 300 # segundos: acima disso a página escurece a célula
    CACHE_TTL   = 30  # o poll é de 15s; 1 em cada 2 requisições paga as sondas

    before_action :authenticate_device!

    def show
      payload = Rails.cache.fetch("hud/payload", expires_in: CACHE_TTL) do
        {
          schema_version: 1,
          fetched_at: Time.current.to_i,
          stale_after: STALE_AFTER,
          cells: HudPayloadService.call
        }
      end

      render json: payload
    end

    private

    def authenticate_device!
      @device = HudDevice.authenticate(bearer_token)
      return head :unauthorized unless @device

      @device.touch_seen!(version: request.user_agent)
    end

    def bearer_token
      request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]
    end
  end
end
