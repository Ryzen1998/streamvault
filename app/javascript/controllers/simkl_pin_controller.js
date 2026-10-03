import { Controller } from "@hotwired/stimulus"

// Polls the server while the user approves StreamVault on simkl.com/pin,
// at the interval Simkl asked for.
export default class extends Controller {
  static targets = ["message"]
  static values = { statusUrl: String, doneUrl: String, interval: { type: Number, default: 5 } }

  connect() {
    this.schedule()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  schedule() {
    this.timer = setTimeout(() => this.poll(), this.intervalValue * 1000)
  }

  async poll() {
    try {
      const response = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
      const data = await response.json()
      if (data.state === "connected") {
        window.location.assign(this.doneUrlValue)
        return
      }
      if (data.state === "expired") {
        this.messageTarget.textContent = "This code expired. Go back to Settings and start again."
        return
      }
      if (data.state === "error") {
        this.messageTarget.textContent = data.message || "Simkl returned an error. Go back to Settings and try again."
        return
      }
    } catch {
      // Network blip: keep waiting.
    }
    this.schedule()
  }
}
