import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const COLORS = { cpu: "#39FF14", ram: "#22d3ee", disk: "#e8f4f8" }
const EMPTY  = "#1f2937"
const SEGS   = 40

export default class extends Controller {
  static targets = ["cpuBar", "cpuPct", "ramBar", "ramPct", "diskBar", "diskPct"]

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "HostStatsChannel" },
      { received: (data) => { if (!data.error) this.update(data) } }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  update({ cpu, ram, disk }) {
    if (cpu  != null) this.setBar("cpu",  cpu)
    if (ram  != null) this.setBar("ram",  ram)
    if (disk != null) this.setBar("disk", disk)
  }

  setBar(name, pct) {
    const filled = Math.min(Math.round(pct * SEGS / 100), SEGS)
    const bar    = this[`${name}BarTarget`]
    const label  = this[`${name}PctTarget`]
    if (bar) {
      bar.querySelectorAll("div").forEach((seg, i) => {
        seg.style.background = i < filled ? COLORS[name] : EMPTY
      })
    }
    if (label) label.textContent = `${pct.toFixed(1)}%`
  }
}
