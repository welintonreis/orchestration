require "test_helper"

# O desktop não é confiável: sem token válido não sai resumo nenhum, e revogar
# tem de valer na requisição seguinte.
class Internal::HudControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    @device, @token = HudDevice.issue!(name: "PC de teste")
  end

  test "sem token é 401" do
    get internal_hud_url
    assert_response :unauthorized
  end

  test "token inválido é 401" do
    get internal_hud_url, headers: { "Authorization" => "Bearer nao-existe" }
    assert_response :unauthorized
  end

  test "token válido devolve o contrato e marca o último contato" do
    with_stub(HudPayloadService, :call, [ { id: "resources", label: "Recursos" } ]) do
      get internal_hud_url, headers: { "Authorization" => "Bearer #{@token}" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["schema_version"]
    assert_equal 300, body["stale_after"]
    assert_equal [ "resources" ], body["cells"].map { |c| c["id"] }
    assert_not_nil @device.reload.last_seen_at
  end

  test "dispositivo revogado perde acesso na hora" do
    @device.revoke!
    get internal_hud_url, headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :unauthorized
  end

  test "o token nunca é guardado em claro" do
    assert_not_equal @token, @device.token_digest
    assert_nil HudDevice.find_by(token_digest: @token)
  end
end
