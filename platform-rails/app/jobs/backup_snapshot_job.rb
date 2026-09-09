class BackupSnapshotJob < ApplicationJob
  queue_as :default

  def perform
    result = WalgInspectorService.call
    latest = result.backups.first
    # A lista já está em mãos aqui; consultá-la de novo custa um container
    # aws-cli, o que é inaceitável no poll de 15s da orelhinha. Então o resumo
    # da corrente de deltas é gravado junto, e o HUD só lê a linha.
    chain = delta_chain(result.backups)

    BackupSnapshot.create!(
      server: "master",
      total_bytes: result.total_bytes,
      object_count: result.object_count,
      last_backup_name: latest&.name,
      last_backup_type: latest&.type,
      last_backup_at: latest&.time,
      full_count: chain[:full_count],
      delta_count: chain[:delta_count],
      deltas_since_full: chain[:deltas_since_full],
      last_full_at: chain[:last_full_at],
      error: result.ok? ? nil : result.error,
      captured_at: Time.current
    )
  end

  private

  # `backups` vem do mais novo para o mais velho (WalgInspectorService ordena
  # assim). A corrente é quantos DELTA existem antes de topar no primeiro FULL:
  # é o que um restore teria de percorrer.
  def delta_chain(backups)
    since = backups.take_while { |b| b.type == "DELTA" }.size
    last_full = backups.find { |b| b.type == "FULL" }
    { full_count: backups.count { |b| b.type == "FULL" },
      delta_count: backups.count { |b| b.type == "DELTA" },
      deltas_since_full: since,
      last_full_at: last_full&.time }
  end
end
