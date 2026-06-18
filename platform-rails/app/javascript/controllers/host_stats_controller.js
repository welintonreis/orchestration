import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const TICK_COUNT = 40
const DIM = "var(--gauge-track)"

export default class extends Controller {
  static targets = [
    "cpuTicks", "cpuPct",
    "ramTicks", "ramPct",
    "diskTicks", "diskPct",
    "swapTicks", "swapPct",
  ]

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "HostStatsChannel" },
      { received: (data) => { if (!data.error) this.update(data) } }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  update({ cpu, ram, disk, swap }) {
    if (cpu  != null) this.setGauge("cpu",  cpu)
    if (ram  != null) this.setGauge("ram",  ram)
    if (disk != null) this.setGauge("disk", disk)
    if (swap != null) this.setGauge("swap", swap)
  }

  setGauge(name, pct) {
    const clamped = Math.min(Math.max(pct, 0), 100)
    const ticksEl = this[`${name}TicksTarget`]
    const label   = this[`${name}PctTarget`]

    if (ticksEl) {
      const color  = ticksEl.dataset.color
      const filled = Math.round((clamped / 100) * TICK_COUNT)
      ticksEl.querySelectorAll("line").forEach((line, i) => {
        line.setAttribute("stroke", i < filled ? color : DIM)
      })
    }
    if (label) label.textContent = `${pct.toFixed(0)}%`
  }
}
