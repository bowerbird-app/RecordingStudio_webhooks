import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    if (this.element && typeof this.element.requestSubmit === "function") {
      this.element.requestSubmit()
    }
  }
}
