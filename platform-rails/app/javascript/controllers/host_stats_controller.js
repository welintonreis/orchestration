import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

const SEGS = 100 // not used for donuts, kept for reference of historical bar count

export default class extends Controller {
  static targets = [
    "cpuCircle", "cpuPct",
    "ramCircle", "ramPct",
    "diskCircle", "diskPct",
    "swapCircle", "swapPct",
  ]

  static values = { circumference: Number }

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
    const circle  = this[`${name}CircleTarget`]
    const label   = this[`${name}PctTarget`]
    const circumference = this.circumferenceValue

    if (circle && circumference) {
      const offset = circumference * (1 - clamped / 100)
      circle.style.strokeDashoffset = offset
    }
    if (label) label.textContent = `${pct.toFixed(0)}%`
  }
}
