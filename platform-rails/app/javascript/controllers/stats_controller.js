import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["cpuBar", "cpuText", "memBar", "memText"]
  static values  = { containerId: String, endpoint: String }

  connect() {
    this.consumer     = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel:      "StatsChannel",
        container_id: this.containerIdValue,
        endpoint:     this.endpointValue
      },
      {
        received: (data) => {
          if (data.stats) this.updateStats(data.stats)
        }
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  updateStats(stats) {
    const cpu = this.calcCpu(stats)
    const mem = this.calcMem(stats)

    if (this.hasCpuBarTarget)  this.updateSegments(this.cpuBarTarget, cpu)
    if (this.hasCpuTextTarget) this.cpuTextTarget.textContent = `${cpu.toFixed(1)}%`
    if (this.hasMemBarTarget)  this.updateSegments(this.memBarTarget, mem)
    if (this.hasMemTextTarget) this.memTextTarget.textContent = `${mem.toFixed(1)}%`
  }

  updateSegments(container, pct) {
    const segs   = Array.from(container.querySelectorAll("[data-index]"))
    const filled = Math.round((pct / 100) * segs.length)
    const color  = this.segColor(pct)
    segs.forEach((seg, i) => {
      seg.classList.remove("bg-gray-700", "bg-green-400", "bg-yellow-400", "bg-red-400")
      seg.classList.add(i < filled ? color : "bg-gray-700")
    })
  }

  calcCpu(stats) {
    try {
      const cur  = stats.cpu_stats
      const prev = stats.precpu_stats
      const cpuDelta    = cur.cpu_usage.total_usage - prev.cpu_usage.total_usage
      const systemDelta = cur.system_cpu_usage     - prev.system_cpu_usage
      const numCpu      = cur.online_cpus || cur.cpu_usage.percpu_usage?.length || 1
      return systemDelta > 0 ? (cpuDelta / systemDelta) * numCpu * 100 : 0
    } catch { return 0 }
  }

  calcMem(stats) {
    try {
      const usage = stats.memory_stats.usage - (stats.memory_stats.stats?.cache || 0)
      const limit = stats.memory_stats.limit
      return limit > 0 ? (usage / limit) * 100 : 0
    } catch { return 0 }
  }

  segColor(pct) {
    if (pct >= 80) return "bg-red-400"
    if (pct >= 60) return "bg-yellow-400"
    return "bg-green-400"
  }
}
