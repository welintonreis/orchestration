import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["type", "endpoint"]

  connect() {
    this.updatePlaceholder()
  }

  updatePlaceholder() {
    const placeholders = {
      unix: "unix:///var/run/docker.sock",
      tcp: "tcp://192.168.1.1:2375"
    }
    this.endpointTarget.placeholder = placeholders[this.typeTarget.value] || ""
  }
}
