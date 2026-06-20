import { Controller } from "@hotwired/stimulus"

// Reloads a target turbo-frame in place. The frame carries refresh="morph",
// so reload() morphs the rows instead of replacing them — filters, the focused
// search box, and scroll position survive, and swarm-recreated containers show
// up without a full-page F5.
export default class extends Controller {
  static values = { frame: String }

  reload() {
    const frame = document.getElementById(this.frameValue)
    if (frame && typeof frame.reload === "function") frame.reload()
  }
}
