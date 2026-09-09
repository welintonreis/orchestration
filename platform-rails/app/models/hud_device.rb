require "digest"

# HudDevice — uma máquina autorizada a ler o resumo do Notch (HUD).
#
# Mesma fronteira do EdgeNode: o desktop NÃO é confiável, o servidor é a
# autoridade. Guardamos só o digest do token, o acesso é de leitura e só do
# resumo que a pill desenha — nada administrativo, nada de Docker por aqui.
#
# Contrato do payload: 00_docs/hud-contract.md do repo redhusky-hud.
class HudDevice < ApplicationRecord
  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  # Devolve [device, token_cru]. O cru aparece UMA vez, na criação — é o que o
  # operador cola no config.json da máquina, e não é recuperável depois.
  def self.issue!(name:)
    raw = SecureRandom.hex(32)
    [ create!(name: name, token_digest: digest(raw)), raw ]
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def self.authenticate(raw)
    return nil if raw.blank?

    active.find_by(token_digest: digest(raw))
  end

  def revoke! = update!(revoked_at: Time.current)
  def revoked? = revoked_at.present?

  # Telemetria de suporte ("o HUD daquela máquina ainda fala com a gente?").
  # update_columns porque isto roda a cada 15s de poll: sem callback, sem
  # updated_at, sem trilha de auditoria.
  def touch_seen!(version: nil)
    update_columns(last_seen_at: Time.current, agent_version: version.presence || agent_version)
  end
end
