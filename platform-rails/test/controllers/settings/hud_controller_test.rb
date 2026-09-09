require "test_helper"

# A tela de dispositivos é o único caminho para emitir o token. Se ela quebrar,
# o Notch não tem como ser instalada em máquina nenhuma.
class Settings::HudControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin_user)
    sign_in @user
  end

  test "index renderiza mesmo sem nenhum dispositivo" do
    HudDevice.delete_all
    get settings_hud_url
    assert_response :success
    assert_match "Nenhum dispositivo autorizado ainda", response.body
  end

  test "index lista os dispositivos existentes" do
    HudDevice.issue!(name: "PC da recepção")
    get settings_hud_url
    assert_response :success
    assert_match "PC da recepção", response.body
  end

  test "gerar token cria o dispositivo e devolve o config pronto, com o token uma vez só" do
    assert_difference "HudDevice.count", 1 do
      post settings_hud_url, params: { device_name: "PC do Welinton" }
    end
    follow_redirect!

    config = JSON.parse(flash[:hud_config])
    token  = config.dig("sources", 0, "token")
    assert_equal "/internal/hud", URI(config.dig("sources", 0, "url")).path
    assert_equal HudDevice.order(:created_at).last, HudDevice.authenticate(token),
                 "o config tem de trazer o token que autentica o dispositivo criado"
    assert_nil HudDevice.find_by(token_digest: token), "só o digest é persistido"
  end

  test "nome em branco não cria dispositivo" do
    assert_no_difference "HudDevice.count" do
      post settings_hud_url, params: { device_name: "  " }
    end
    assert_redirected_to settings_hud_path
  end

  test "revogar tira o acesso do dispositivo" do
    device, token = HudDevice.issue!(name: "PC velho")

    post settings_revoke_hud_url(device)

    assert device.reload.revoked?
    assert_nil HudDevice.authenticate(token)
  end
end
