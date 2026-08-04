import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundDocumentClick = this.handleDocumentClick.bind(this)
    document.addEventListener("click", this.boundDocumentClick, true)
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick, true)
  }

  handleDocumentClick(event) {
    this.syncPresetInput(event)
    this.queueDateRangeSubmit(event)
  }

  syncPresetInput(event) {
    const commandButton = event.target.closest("[data-flat-pack-date-picker-command]")
    if (!commandButton) {
      return
    }

    const panel = commandButton.closest("[role='dialog']")
    const panelId = panel?.id
    if (!panelId) {
      return
    }

    const trigger = this.element.querySelector(`[aria-controls='${CSS.escape(panelId)}']`)
    if (!trigger) {
      return
    }

    const presetInput = this.element.querySelector("input[type='hidden'][name$='date_range_preset']")
    if (!presetInput) {
      return
    }

    const command = commandButton.dataset.flatPackDatePickerCommand
    if (command === "preset") {
      presetInput.value = commandButton.dataset.flatPackDatePickerPreset || ""
    } else if (command === "day") {
      presetInput.value = ""
    }
  }

  queueDateRangeSubmit(event) {
    if (event.recordingStudioWebhooksDateSubmitQueued) {
      return
    }

    const applyButton = event.target.closest("[data-flat-pack-date-picker-command='apply']")
    if (!applyButton) {
      return
    }

    const panel = applyButton.closest("[role='dialog']")
    const panelId = panel?.id
    if (!panelId) {
      return
    }

    const trigger = this.element.querySelector(`[aria-controls='${CSS.escape(panelId)}']`)
    if (!trigger) {
      return
    }

    const form = trigger.closest("form")
    if (!form || form.id === "screen-filters-mobile-form") {
      return
    }

    event.recordingStudioWebhooksDateSubmitQueued = true

    window.setTimeout(() => {
      const autoSubmit = this.application.getControllerForElementAndIdentifier(
        form,
        "flat-pack--auto-submit"
      )

      if (autoSubmit && typeof autoSubmit.queueSubmit === "function") {
        autoSubmit.queueSubmit()
        return
      }

      if (form.requestSubmit) {
        form.requestSubmit()
        return
      }

      form.submit()
    }, 0)
  }
}
