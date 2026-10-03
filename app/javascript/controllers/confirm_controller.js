import { Controller } from "@hotwired/stimulus"

// Asks before a destructive form submits. The app loads neither Turbo nor
// rails-ujs, so data-confirm / data-turbo-confirm attributes do nothing.
//   button_to "Remove", path, method: :delete,
//     form: { data: { controller: "confirm", action: "submit->confirm#ask", confirm_message_value: "..." } }
export default class extends Controller {
  static values = { message: String }

  ask(event) {
    if (!window.confirm(this.messageValue)) event.preventDefault()
  }
}
