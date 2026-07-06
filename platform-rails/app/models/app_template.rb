# One-click deploy templates (feature-app-templates.md). A template is a
# docker-compose YAML with `{{VAR}}` placeholders; `variables` documents each
# placeholder's label/default for the deploy form. Admin-editable, but the
# actual deploy action is operator+ (Authorization's fail-closed default —
# no POLICY override needed, same as every other stack mutation).
class AppTemplate < ApplicationRecord
  # Real host paths a rendered template is allowed to bind-mount — anything
  # else (and the docker socket, unconditionally) is refused at deploy time.
  # A template is admin-editable; without this, a compromised admin account
  # (or a copy-pasted bad template) turns every operator's one-click deploy
  # into host root via a socket mount or an arbitrary host path bind.
  ALLOWED_HOST_PATH_PREFIXES = %w[/srv/redhusky/].freeze

  validates :name, presence: true, uniqueness: true
  validates :compose_yaml, presence: true

  VAR_PATTERN = /\{\{\s*(\w+)\s*\}\}/

  # placeholders actually referenced in compose_yaml, in first-seen order —
  # drives the deploy form even if `variables` metadata is incomplete/stale.
  def placeholders
    compose_yaml.scan(VAR_PATTERN).flatten.uniq
  end

  def render_compose(values = {})
    compose_yaml.gsub(VAR_PATTERN) { values[$1].presence || values[$1.to_sym].presence || "" }
  end

  # Returns [safe_boolean, reason_or_nil]. Parses the RENDERED yaml (not the
  # template) since a placeholder could in principle be abused to smuggle in
  # a bind mount — check what will actually be deployed.
  def self.check_safety(rendered_yaml)
    doc = YAML.safe_load(rendered_yaml, permitted_classes: [ Symbol ], aliases: true)
    return [ false, "YAML inválido: não é um compose válido (nenhum mapeamento no topo)" ] unless doc.is_a?(Hash)

    Array(doc["services"]).each do |name, svc|
      Array(svc&.dig("volumes")).each do |vol|
        source = vol.is_a?(String) ? vol.split(":").first : vol["source"]
        next unless source.to_s.start_with?("/") # bind mount (not a named volume)
        return [ false, "serviço \"#{name}\": monta o socket do Docker" ] if source == "/var/run/docker.sock"
        allowed = ALLOWED_HOST_PATH_PREFIXES.any? { |p| source.start_with?(p) }
        return [ false, "serviço \"#{name}\": bind mount de path do host fora do permitido (#{source})" ] unless allowed
      end
    end
    [ true, nil ]
  rescue Psych::SyntaxError => e
    [ false, "YAML inválido: #{e.message}" ]
  end
end
