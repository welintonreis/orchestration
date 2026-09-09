require "test_helper"

# O valor da orelhinha está nos denominadores: cada item tem de virar um % que
# significa alguma coisa. Estes testes travam justamente isso — a fração e a
# severidade de cada janela, não o texto.
class HudPayloadServiceTest < ActiveSupport::TestCase
  setup { @svc = HudPayloadService.new }

  def win(cell, label) = cell[:windows].find { |w| w[:label] == label }

  # ── Recursos ───────────────────────────────────────────────────────────
  test "recursos: % é uso, cor é o limiar do MetricsJob, e o anel segue o pior" do
    HostMetric.create!(cpu_percent: 90, ram_percent: 45, disk_percent: 40, swap_percent: 0,
                       load_1m: 1, load_5m: 1, load_15m: 1)

    cell = @svc.send(:resources_cell)

    assert_equal %w[Uptime CPU RAM Disco Swap], cell[:windows].map { |w| w[:label] }
    assert_equal 0.9, win(cell, "CPU")[:progress], "a barra é o uso real"
    assert_equal 1.0, win(cell, "CPU")[:severity], "90% com alerta em 85% já é crítico"
    assert_equal 0.5, win(cell, "Disco")[:severity], "40% de 80% de limiar = meia régua"
    assert_equal 0.9, cell[:progress], "o anel mostra o recurso mais apertado"
    assert_equal 1.0, cell[:severity]
  end

  test "recursos: uptime é fração da janela de reboot, e passar dela é amarelo" do
    HostMetric.create!(cpu_percent: 1, ram_percent: 1, disk_percent: 1, swap_percent: 0,
                       load_1m: 0, load_5m: 0, load_15m: 0)

    w = win(@svc.send(:resources_cell), "Uptime")

    assert_operator w[:progress], :<=, 1.0
    assert_includes [ 0.0, 0.5 ], w[:severity], "uptime alto avisa, não vira incêndio"
  end

  test "recursos: sem leitura de host a célula é omitida, não zerada" do
    HostMetric.delete_all
    assert_nil @svc.send(:resources_cell), "zerar faria parecer máquina saudável"
  end

  # ── Docker ─────────────────────────────────────────────────────────────
  test "docker: services é tarefas no ar sobre desejadas; falta vira severidade" do
    cell = docker_cell_with(
      services: [ svc_stub("a_web", desired: 3, running: 3, stack: "a"),
                  svc_stub("b_web", desired: 1, running: 0, stack: "b") ]
    )

    assert_equal "3/4", win(cell, "Services")[:value]
    assert_equal 0.75, win(cell, "Services")[:progress]
    assert_equal 0.25, win(cell, "Services")[:severity]
    assert_equal 0.75, cell[:progress], "o anel do Docker é convergência"
  end

  test "docker: stack com serviço escalado a zero não conta como doente" do
    cell = docker_cell_with(
      services: [ svc_stub("a_web", desired: 0, running: 0, stack: "a"),
                  svc_stub("b_web", desired: 2, running: 2, stack: "b") ]
    )

    assert_equal "2/2", win(cell, "Stacks")[:value]
    assert_equal 0.0, win(cell, "Stacks")[:severity]
  end

  test "docker: images/volumes medem desperdício e nunca passam de amarelo" do
    cell = docker_cell_with(
      df: { "Images"  => [ { "Containers" => 0, "Size" => 100 }, { "Containers" => 2, "Size" => 100 } ],
            "Volumes" => [ { "UsageData" => { "RefCount" => 0, "Size" => 10 } } ] * 4 }
    )

    assert_equal 0.5, win(cell, "Images")[:progress], "metade das imagens sem container"
    assert_operator win(cell, "Images")[:severity], :<=, 0.6
    assert_equal 0.0, win(cell, "Volumes")[:progress], "nenhum volume em uso"
    assert_operator win(cell, "Volumes")[:severity], :<=, 0.6, "lixo acumulado não é incidente"
  end

  test "docker: rede referenciada por container ou serviço conta como em uso" do
    cell = docker_cell_with(
      services: [ svc_stub("a_web", desired: 1, running: 1, stack: "a", networks: [ "net-id-2" ]) ],
      containers: [ { "State" => "running",
                      "NetworkSettings" => { "Networks" => { "traefik" => { "NetworkID" => "net-id-1" } } } } ],
      networks: [ { "Id" => "net-id-1", "Name" => "traefik" },
                  { "Id" => "net-id-2", "Name" => "postgres-cluster" },
                  { "Id" => "net-id-3", "Name" => "orfa" },
                  { "Id" => "net-id-4", "Name" => "bridge" } ]
    )

    assert_equal "3/4", win(cell, "Networks")[:value], "bridge é do Docker, nunca é órfã"
  end

  test "docker: socket fora do ar omite a célula inteira" do
    with_stub(DockerClient, :new, -> { raise DockerClient::Error, "sem socket" }) do
      assert_nil @svc.send(:docker_cell)
    end
  end

  # ── Bancos ─────────────────────────────────────────────────────────────
  test "backups: a barra é a idade sobre o RPO de 24h" do
    BackupSnapshot.create!(server: "master", captured_at: Time.current,
                           last_backup_at: 6.hours.ago, last_backup_type: "FULL")

    w = @svc.send(:backups_window)

    assert_equal 0.25, w[:progress], "6h de 24h de RPO"
    assert_equal 0.25, w[:severity]
  end

  test "backups: passar do RPO enche a barra e fica vermelho" do
    BackupSnapshot.create!(server: "master", captured_at: Time.current,
                           last_backup_at: 7.days.ago, last_backup_type: "FULL")

    w = @svc.send(:backups_window)

    assert_equal 1.0, w[:progress]
    assert_equal 1.0, w[:severity], "backup de uma semana atrás é incidente, não aviso"
  end

  test "backups: erro do wal-g é crítico, e não uma célula vazia" do
    BackupSnapshot.create!(server: "master", captured_at: Time.current, error: "container parado")

    assert_equal 1.0, @svc.send(:backups_window)[:severity]
  end

  test "deltas: a barra é o tamanho da corrente sobre o teto do ciclo" do
    BackupSnapshot.create!(server: "master", captured_at: Time.current,
                           last_backup_at: 1.hour.ago, deltas_since_full: 3)

    w = @svc.send(:deltas_window)

    assert_equal "3/6", w[:value]
    assert_equal 0.5, w[:progress]
  end

  test "bancos: sem nenhuma sonda respondendo a célula é omitida" do
    BackupSnapshot.delete_all
    with_stub(@svc, :pg_connect, nil) do
      with_stub(@svc, :rabbit_get, nil) do
        assert_nil @svc.send(:databases_cell)
      end
    end
  end

  private

  def svc_stub(name, desired:, running:, stack:, networks: [])
    { "Spec" => { "Name" => name, "Labels" => { "com.docker.stack.namespace" => stack },
                  "TaskTemplate" => { "Networks" => networks.map { |n| { "Target" => n } } } },
      "ServiceStatus" => { "DesiredTasks" => desired, "RunningTasks" => running } }
  end

  def docker_cell_with(services: [], containers: [], df: {}, networks: [])
    client = Object.new
    client.define_singleton_method(:services)   { services }
    client.define_singleton_method(:containers) { |*| containers }
    client.define_singleton_method(:system_df)  { |*| df }
    client.define_singleton_method(:networks)   { networks }
    with_stub(DockerClient, :new, client) { @svc.send(:docker_cell) }
  end
end
