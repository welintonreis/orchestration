import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["output"]
  static values  = { containerId: String, endpoint: String, tail: Number }

  connect() {
    this.consumer     = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel:      "LogsChannel",
        container_id: this.containerIdValue,
        endpoint:     this.endpointValue,
        tail:         this.tailValue || 200
      },
      {
        received: (data) => {
          if (data.error) {
            this.appendLine(`[error] ${data.error}`)
          } else if (data.chunk) {
            this.appendChunk(data.chunk)
          }
        }
      }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  appendChunk(chunk) {
    const el = this.outputTarget
    el.textContent += chunk
    el.scrollTop = el.scrollHeight
  }

  appendLine(text) {
    const el = this.outputTarget
    el.textContent += text + "\n"
    el.scrollTop = el.scrollHeight
  }
}
